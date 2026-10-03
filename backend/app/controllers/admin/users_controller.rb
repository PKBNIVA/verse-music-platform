module Admin
  class UsersController < BaseController
    include AdminPagination

    # Server-side search across every user (not just the newest page): `q` matches
    # name/email (ILIKE) or an exact id; `role`/`status` filter to a known enum value.
    def index
      scope = User.includes(:profile).order(created_at: :desc)
      scope = scope.where(role: params[:role]) if params[:role].present? && User.roles.key?(params[:role].to_s)
      scope = scope.where(status: params[:status]) if params[:status].present? && User.statuses.key?(params[:status].to_s)
      if params[:q].present?
        q = params[:q].to_s.strip.first(254)
        like = "%#{q.gsub(/[\\%_]/) { "\\#{_1}" }}%"
        scope = scope.where("users.name ILIKE :like OR users.email ILIKE :like OR users.id = :id", like: like, id: q)
      end
      rows, meta = admin_paginate(scope)
      early_access_until = Subscription.where(user_id: rows.map(&:id), status: "early_access").pluck(:user_id, :trial_ends_at).to_h
      sign_in_methods = unverified_sign_in_methods(rows)
      render json: { users: rows.map { public_user(_1).merge("createdAt" => _1.created_at, "earlyAccessUntil" => early_access_until[_1.id]).merge(sign_in_methods[_1.id] || {}) } }.merge(meta)
    end

    # For unconfirmed accounts only: what else can sign in to them (linked identities, phone), so
    # support can spot a stranger's pre-registration before confirming the email by hand.
    # The phone is masked to its last four digits.
    def unverified_sign_in_methods(rows)
      ids = rows.reject { _1.email_verified? || _1.admin? }.map(&:id)
      return {} if ids.empty?
      connections = AuthConnection.where(owner_type: "User", owner_id: ids).order(:created_at).group_by(&:owner_id)
      rows.select { ids.include?(_1.id) }.to_h do |user|
        [user.id, {
          "connections" => (connections[user.id] || []).map { { "provider" => _1.provider, "email" => _1.email } },
          "phone" => (user.phone.present? ? "•••• #{user.phone.to_s.gsub(/\D/, "").last(4)}" : nil),
          "phoneVerified" => user.phone_verified_at.present?
        }]
      end
    end

    def update
      return render_error("You cannot change your own admin status.", :conflict) if params[:id] == current_user.id
      return render_error("Invalid user status.", :bad_request) unless %w[active suspended pending].include?(params[:status])
      user = User.find(params[:id])
      return render_error("This account was deleted by its owner and cannot be restored.", :conflict, "ACCOUNT_DELETED") if user.deleted?
      user.update!(status: params[:status])
      Session.revoke!(user.sessions) unless user.active?
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
      suppression = email_suppression(email)
      unless user
        diagnosis = [{ level: "error", code: "NO_ACCOUNT", message: "No account uses this email. Check the spelling, other addresses they may have used, or ask them to register." }]
        diagnosis << code_note(codes, email_provider) if codes && codes[:outstanding].positive?
        diagnosis << suppression_note(suppression)
        return render(json: { email:, exists: false, emailProviderConfigured: email_provider, recentFailedLogins: failed_logins, signInCodes: codes, emailSuppression: suppression, diagnosis: diagnosis.compact })
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
                active_sessions:, recent_sessions:, tokens:, email_provider:, failed_logins:, codes:, suppression: }

      render json: {
        email:, exists: true,
        user: { id: user.id, name: user.name, role: user.role, status: user.status, emailVerified: user.email_verified?, profileComplete: user.profile_complete?,
                passwordSet: facts[:password_set], createdAt: user.created_at, lastLoginAt: user.last_login_at },
        sessions: { active: active_sessions, createdLast7Days: recent_sessions, cap: AuthController::MAX_LIVE_SESSIONS },
        emailTokens: tokens, signInCodes: codes, recentAuthEvents: events, recentFailedLogins: failed_logins,
        emailProviderConfigured: email_provider, emailSuppression: suppression, diagnosis: diagnose(user, facts)
      }
    end

    def revoke_sessions
      user = User.find(params[:id])
      return render_error("Use sign out to end your own sessions.", :conflict) if user.id == current_user.id
      count = Session.revoke!(user.sessions)
      audit!("admin.user.revoke_sessions", user, count:)
      render json: { ok: true, revoked: count }
    end

    # Support rescue for an unverified account whose address cannot receive mail (bounce, typo):
    # password sign-in is refused until the email is confirmed, so an admin can confirm it here.
    def confirm_email
      user = User.find(params[:id])
      return render_error("This account was deleted by its owner.", :conflict, "ACCOUNT_DELETED") if user.deleted?
      return render_error("Admin accounts do not need email confirmation.", :unprocessable_content) if user.admin?

      was_verified = user.email_verified?
      user.update!(email_verified: true)
      audit!("admin.user.confirm_email", user, alreadyVerified: was_verified)
      render json: { ok: true, alreadyVerified: was_verified }
    end

    # Read-only: the account's billing details (current and earlier versions) and invoices.
    def billing
      user = User.find(params[:id])
      profiles = BillingProfile.where(user_id: user.id).order(version: :desc).limit(20)
      render json: { profile: profiles.find(&:current)&.as_json_for_owner, versions: profiles.map(&:as_json_for_owner),
                     invoices: TaxInvoice.where(user_id: user.id).newest_first.limit(100).map(&:list_json) }
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

    # Early Access Pro (config/billing.yml `early_access`): grants the first `seats` employer
    # accounts a free run of Pro for `days` days, no card required. Employer/hirer accounts only,
    # never a paying customer, and never past the configured seat count — a seat, once granted, is
    # never freed back up even if later revoked (see the `early_access` column on Subscription).
    def grant_early_access
      user = User.find(params[:id])
      subscription, refusal = EarlyAccessGrant.call(user:)
      return render_error(refusal.message, refusal.status, refusal.code) if refusal

      seats_taken = EarlyAccessGrant.seats_taken
      audit!("admin.early_access.grant", subscription, seatsTaken: seats_taken, seats: BillingConfig.early_access_seats)
      Notifier.early_access_granted(subscription)
      render json: { id: subscription.id, trialEndsAt: subscription.trial_ends_at }, status: :created
    end

    def revoke_early_access
      subscription = Subscription.where(user_id: params[:id], status: "early_access").order(created_at: :desc).first
      return render_error("This account has no active Early Access Pro grant.", :not_found) unless subscription

      subscription.update!(status: "cancelled")
      audit!("admin.early_access.revoke", subscription)
      render json: { ok: true }
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
      [code_note(facts[:codes], facts[:email_provider]), suppression_note(facts[:suppression])].compact.each do |note|
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
      if user.admin?
        case AuthController.admin_second_factor_state(user.email)
        when :skipped
          add.call("warn", "ADMIN_SECOND_FACTOR_SKIPPED", AuthController.admin_second_factor_warning(user.email))
        when :off then add.call("warn", "ADMIN_SECOND_FACTOR_OFF", AuthController::SECOND_FACTOR_DISABLED_WARNING)
        when :unavailable then add.call("error", "ADMIN_SECOND_FACTOR_UNAVAILABLE", "ADMIN_SECOND_FACTOR=required but the code cannot be emailed to this admin (no email provider, or the address is suppressed), so their password sign-in is refused. Fix email, or set ADMIN_SECOND_FACTOR=auto.")
        end
      end
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

    # What the email provider reported for this address (EmailSuppression), or nil.
    def email_suppression(email)
      row = EmailSuppression.find_by(email:)
      row && { scope: row.scope, reason: row.reason, lastEvent: row.last_event, lastEventAt: row.last_event_at,
               suppressedAt: row.suppressed_at, softBounces: row.soft_bounce_count }
    end

    def suppression_note(suppression)
      case suppression&.dig(:scope)
      when "all"
        { level: "error", code: "EMAIL_SUPPRESSED", message: "Email to this address is suppressed (#{suppression[:reason].tr('_', ' ')} reported by the email provider), so sign-in codes, verification and reset emails are not sent. They need a different address or their password; if the mailbox is fixed, remove the address from the provider's blocklist and from email suppressions." }
      when "notifications"
        { level: "info", code: "EMAIL_UNSUBSCRIBED", message: "Unsubscribed at the email provider: notification emails are not sent. Sign-in and security emails still are." }
      when "none"
        { level: "info", code: "EMAIL_SOFT_BOUNCES", message: "#{suppression[:softBounces]} temporary delivery failure(s) (mailbox full or greylisted). Delivery is still attempted." }
      end
    end

    def masked_ip(ip)
      return nil if ip.blank?
      ip = ip.to_s
      ip.include?(":") ? "#{ip.split(':').first(2).join(':')}:…" : ip.split(".").first(2).join(".") + ".x.x"
    end
  end
end
