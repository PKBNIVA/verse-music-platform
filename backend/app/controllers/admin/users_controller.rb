module Admin
  class UsersController < BaseController
    def index = render(json: { users: User.includes(:profile).order(created_at: :desc).limit(500).map { public_user(_1).merge("createdAt" => _1.created_at) } })

    def update
      return render_error("You cannot change your own admin status.", :conflict) if params[:id] == current_user.id
      return render_error("Invalid user status.", :bad_request) unless %w[active suspended pending].include?(params[:status])
      user = User.find(params[:id])
      user.update!(status: params[:status])
      user.sessions.delete_all unless user.active?
      audit!("admin.user.status", user, status: user.status)
      render json: { ok: true }
    end

    # Sign-in doctor: everything an admin needs to explain why someone cannot sign in,
    # without exposing secrets (no password digest, token digests or full IP addresses).
    def lookup
      email = params[:email].is_a?(String) ? params[:email].strip.downcase : ""
      return render_error("Enter an email address.", :bad_request, "EMAIL_REQUIRED") if email.blank? || email.include?("\u0000") || email.length > 254

      user = User.includes(:profile).find_by(email:)
      audit!("admin.user.lookup", user, found: user.present?)
      email_provider = EmailDelivery.configured?
      failed_logins = recent_login_failures(email)
      codes = sign_in_codes(email)
      unless user
        diagnosis = [{ level: "error", code: "NO_ACCOUNT", message: "No account uses this email. Check the spelling, other addresses they may have used, or ask them to register." }]
        diagnosis << code_note(codes, email_provider) if codes && codes[:outstanding].positive?
        return render(json: { email:, exists: false, emailProviderConfigured: email_provider, recentFailedLogins: failed_logins, signInCodes: codes, diagnosis: diagnosis.compact })
      end

      now = Time.current
      sessions = user.sessions
      active_sessions = sessions.where("expires_at > ?", now).count
      recent_sessions = sessions.where("created_at >= ?", 7.days.ago).count
      tokens = user.email_tokens.where("created_at >= ?", 7.days.ago).order(created_at: :desc).limit(20).map do |token|
        { purpose: token.purpose, createdAt: token.created_at, expiresAt: token.expires_at, used: token.used_at.present?, expired: token.used_at.nil? && token.expires_at.present? && token.expires_at <= now }
      end
      events = AuditLog.where(entity_type: "User", entity_id: user.id).where("action LIKE 'auth.%' OR action LIKE 'admin.user.%'").where.not(action: "admin.user.lookup")
        .order(created_at: :desc).limit(20).map { { action: _1.action, at: _1.created_at, ip: masked_ip(_1.metadata.is_a?(Hash) ? (_1.metadata["ip"] || _1.metadata["remoteIp"]) : nil) }.compact }
      facts = { status: user.status, email_verified: user.email_verified?, password_set: user.password_digest.present?, last_login_at: user.last_login_at,
                active_sessions:, recent_sessions:, tokens:, email_provider:, failed_logins:, codes: }

      render json: {
        email:, exists: true,
        user: { id: user.id, name: user.name, role: user.role, status: user.status, emailVerified: user.email_verified?, profileComplete: user.profile_complete?,
                passwordSet: facts[:password_set], createdAt: user.created_at, lastLoginAt: user.last_login_at },
        sessions: { active: active_sessions, createdLast7Days: recent_sessions, cap: AuthController::MAX_LIVE_SESSIONS },
        emailTokens: tokens, signInCodes: codes, recentAuthEvents: events, recentFailedLogins: failed_logins,
        emailProviderConfigured: email_provider, diagnosis: diagnose(user, facts)
      }
    end

    def revoke_sessions
      user = User.find(params[:id])
      return render_error("Use sign out to end your own sessions.", :conflict) if user.id == current_user.id
      count = user.sessions.delete_all
      audit!("admin.user.revoke_sessions", user, count:)
      render json: { ok: true, revoked: count }
    end

    def grant_plan
      return render_error("Invalid plan.", :bad_request) unless %w[pro studio enterprise].include?(params[:planCode])
      days = params.fetch(:days, 30)
      # Whole numbers are clamped to 1..366; anything else ("abc", 1.5, arrays) is rejected rather than read as 0.
      return render_error("Days must be a whole number between 1 and 366.", :bad_request) unless days.is_a?(Integer) || days.to_s.match?(/\A-?\d+\z/)
      user = User.find(params[:id])
      return render_error("Plans can only be granted to professional or organization accounts.", :unprocessable_content) if user.admin?
      Subscription.where(user:, status: %w[active trialing pending]).update_all(status: "cancelled", updated_at: Time.current)
      subscription = Subscription.create!(user:, plan_code: params[:planCode], provider: "internal", status: "active", current_period_start: Time.current, current_period_end: days.to_i.clamp(1, 366).days.from_now)
      audit!("admin.plan.grant", subscription, planCode: subscription.plan_code)
      render json: { id: subscription.id }, status: :created
    end

    private

    # Failed password attempts for this email in the current throttle window (all networks).
    def recent_login_failures(email)
      key = failure_key("login-failure", :email, email, AuthController::LOGIN_FAILURE_PERIOD)
      { count: Rails.cache.increment(key, 0, expires_in: AuthController::LOGIN_FAILURE_PERIOD) || 0,
        windowMinutes: AuthController::LOGIN_FAILURE_PERIOD.in_minutes.to_i,
        perNetworkLimit: AuthController::LOGIN_FAILURES_PER_EMAIL_AND_IP, perEmailLimit: AuthController::LOGIN_FAILURES_PER_EMAIL }
    rescue StandardError
      { count: nil, windowMinutes: AuthController::LOGIN_FAILURE_PERIOD.in_minutes.to_i }
    end

    def diagnose(user, facts)
      notes = []
      add = ->(level, code, message) { notes << { level:, code:, message: } }
      add.call("error", "ACCOUNT_#{user.status.upcase}", "Account is #{user.status}. Sign-in answers “This account is not active.” Restore it from the Users tab if appropriate.") unless user.active?
      add.call("error", "NO_PASSWORD", "No password is set — they must use an email sign-in code or reset their password.") unless facts[:password_set]
      failures = facts[:failed_logins][:count].to_i
      if failures >= AuthController::LOGIN_FAILURES_PER_EMAIL
        add.call("error", "LOGIN_LOCKED", "Sign-in is locked for this email after #{failures} failed attempts. It unlocks within #{facts[:failed_logins][:windowMinutes]} minutes.")
      elsif failures >= AuthController::LOGIN_FAILURES_PER_EMAIL_AND_IP
        add.call("warn", "MANY_FAILURES", "#{failures} failed attempts in the last #{facts[:failed_logins][:windowMinutes]} minutes: a single network is locked out after #{AuthController::LOGIN_FAILURES_PER_EMAIL_AND_IP}. Likely a wrong or old password — suggest a reset.")
      elsif failures.positive?
        add.call("info", "RECENT_FAILURES", "#{failures} recent failed attempt(s) — probably a mistyped or outdated password.")
      end
      if (note = code_note(facts[:codes], facts[:email_provider]))
        add.call(note[:level], note[:code], note[:message])
      end
      add.call("warn", "NEVER_SIGNED_IN", "Has never signed in successfully since registering.") if facts[:last_login_at].nil?
      add.call("info", "EMAIL_NOT_VERIFIED", "Email not verified. This does not block sign-in, but verification emails may not be arriving.") unless facts[:email_verified]
      unused_resets = facts[:tokens].count { _1[:purpose] == "reset_password" && !_1[:used] }
      if unused_resets.positive? && !facts[:email_provider]
        add.call("error", "EMAIL_UNDELIVERABLE", "#{unused_resets} password reset(s) requested but no email provider is configured, so the emails were never sent.")
      elsif unused_resets.positive?
        add.call("warn", "RESET_NOT_COMPLETED", "#{unused_resets} password reset(s) requested in the last 7 days but not completed — check spam or the address.")
      end
      add.call("warn", "EMAIL_PROVIDER_MISSING", "No email provider is configured: verification and reset emails cannot be delivered.") if !facts[:email_provider] && unused_resets.zero?
      cap = AuthController::MAX_LIVE_SESSIONS
      add.call("warn", "SESSION_CAP", "#{facts[:active_sessions]} active sessions (cap #{cap}): each new sign-in signs out the oldest device.") if facts[:active_sessions] >= cap
      add.call("warn", "FREQUENT_RELOGINS", "#{facts[:recent_sessions]} sign-ins in 7 days — sessions are being lost (cleared browser storage, private windows or the session cap).") if facts[:recent_sessions] >= 15
      add.call("ok", "NO_BLOCKERS", "No account-side blocker found. Ask for the exact error message, browser and time of the attempt.") if notes.none? { %w[error warn].include?(_1[:level]) }
      notes
    end

    # Email sign-in (OTP) codes for this address; nil where the feature is not installed.
    def sign_in_codes(email)
      return nil unless defined?(SignInCode) && SignInCode.table_exists?
      outstanding = SignInCode.usable.where(email:)
      { outstanding: outstanding.count, lastRequestedAt: SignInCode.where(email:).maximum(:created_at),
        requestedLast24Hours: SignInCode.where(email:).where("created_at >= ?", 24.hours.ago).count }
    end

    def code_note(codes, email_provider)
      return nil unless codes && codes[:outstanding].positive?
      if email_provider
        { level: "warn", code: "SIGN_IN_CODE_UNUSED", message: "Sign-in code requested but not used — check email delivery (spam folder, typo in the address)." }
      else
        { level: "error", code: "SIGN_IN_CODE_UNDELIVERABLE", message: "Sign-in code requested but no email provider is configured, so it was never sent." }
      end
    end

    def masked_ip(ip)
      return nil if ip.blank?
      ip = ip.to_s
      ip.include?(":") ? "#{ip.split(':').first(2).join(':')}:…" : ip.split(".").first(2).join(".") + ".x.x"
    end
  end
end
