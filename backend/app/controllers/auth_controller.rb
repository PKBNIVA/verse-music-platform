class AuthController < ApplicationController
  include ConsumesSignInCodes

  LOGIN_FAILURE_PERIOD = 15.minutes
  # Strict budget per (email, IP) pair; a looser global per-email budget still
  # stops distributed guessing without letting one attacker lock a user out.
  LOGIN_FAILURES_PER_EMAIL_AND_IP = 10
  LOGIN_FAILURES_PER_EMAIL = 100
  LOGIN_FAILURES_PER_IP = 50
  MAX_LIVE_SESSIONS = 10
  OTP_REQUEST_PERIOD = 1.hour
  OTP_REQUESTS_PER_EMAIL = 5
  # Mobile carriers put many users behind one IP (CGNAT); the per-email limit is the real guard.
  OTP_REQUESTS_PER_IP = 30
  OTP_VERIFY_FAILURE_PERIOD = 15.minutes
  # Per-code attempts are capped by SignInCode::MAX_ATTEMPTS; this IP budget stops
  # one client spraying guesses across many addresses' codes.
  OTP_VERIFY_FAILURES_PER_IP = 25
  OTP_UNAVAILABLE_MESSAGE = "Email sign-in codes are temporarily unavailable. Try again in a few minutes. If you have a confirmed account with a password you can use that, otherwise contact MusiLynk support.".freeze
  OTP_REQUEST_MESSAGE = "If this email can be used on MusiLynk, a 6-digit code is on its way. It expires in 10 minutes.".freeze
  EMAIL_VERIFICATION_REQUIRED_MESSAGE = "Confirm your email address before signing in with a password. We can send the link again, or you can sign in with an emailed code.".freeze
  OTP_INVALID_MESSAGE = "Invalid or expired code.".freeze
  EMAIL_SUPPRESSED_MESSAGE = "Email to this address bounced or was reported as spam, so MusiLynk can no longer send to it. Use a different email address. If this is your address and you cannot sign in, contact MusiLynk support.".freeze
  CODE_ONLY_LOGIN_MESSAGE = "This account uses email codes — send me a code.".freeze
  PASSWORDLESS_LOGIN_MESSAGE = "Use Google to sign in, or set a password from your email.".freeze
  PHONE_OTP_UNAVAILABLE_MESSAGE = "WhatsApp sign-in codes are temporarily unavailable.".freeze
  PHONE_OTP_REQUEST_MESSAGE = "If this number can be used on MusiLynk, a 6-digit code is on its way on WhatsApp. It expires in 10 minutes.".freeze
  PHONE_OTP_INVALID_MESSAGE = "Invalid or expired code.".freeze
  # Admin password sign-in needs a second step: a code emailed to the admin.
  SECOND_FACTOR_PURPOSE = :admin_second_factor
  SECOND_FACTOR_CHALLENGES_PER_EMAIL = 5
  SECOND_FACTOR_CHALLENGE_PERIOD = 1.hour
  SECOND_FACTOR_FAILURES_PER_USER = 10
  SECOND_FACTOR_FAILURES_PER_IP = 25
  SECOND_FACTOR_FAILURE_PERIOD = 15.minutes
  SECOND_FACTOR_MESSAGE = "Admin sign-in needs one more step. We emailed a 6-digit code to your address. It expires in 10 minutes.".freeze
  SECOND_FACTOR_EXPIRED_MESSAGE = "This sign-in step has expired. Sign in with your password again.".freeze
  SECOND_FACTOR_UNAVAILABLE_MESSAGE = "Admin sign-in needs an emailed code, but email delivery is not configured on the server. Configure an email provider to sign in.".freeze
  SECOND_FACTOR_SKIPPED_WARNING = "Admin 2-step sign-in is off because email delivery is not configured. Add an email provider (BREVO_API_KEY), then set ADMIN_SECOND_FACTOR=required.".freeze
  SECOND_FACTOR_SUPPRESSED_WARNING = "Admin 2-step sign-in is off for this admin because email to their address is suppressed (bounced or reported as spam). Fix the address, then lift the suppression.".freeze
  SECOND_FACTOR_ADDRESS_WARNING = "Admin 2-step sign-in is off for this admin because their email address can't receive mail (a reserved domain such as .local or .invalid). Change the admin's email to a real mailbox.".freeze
  SECOND_FACTOR_DISABLED_WARNING = "Admin 2-step sign-in is turned off (ADMIN_SECOND_FACTOR=off). Remove that setting once the emergency is over.".freeze
  # With ADMIN_ORIGIN set, admins sign in only on the admin site (see AdminOrigin).
  ADMIN_USE_ADMIN_SITE_MESSAGE = "Admins sign in at the admin site.".freeze

  # ADMIN_SECOND_FACTOR selects how an admin password sign-in is treated:
  #   "auto" (default, and any unrecognised value): require the emailed code when
  #     codes can be delivered; otherwise allow the password alone, audit it as
  #     auth.admin_second_factor_skipped and warn in the admin tester and sign-in
  #     doctor. Merging or misconfiguring email never locks admins out.
  #   "required": always require the code; without email delivery the password
  #     step fails closed (503 SECOND_FACTOR_UNAVAILABLE).
  #   "off": emergency disable only; every such sign-in is audited.
  # Outside production the on-screen debugCode counts as delivery. With an email
  # address, a suppressed (bounced or complained) address or one on a reserved domain
  # (admin@musilynk.local) counts as undeliverable, so auto mode never sends the code nowhere.
  # Returns :enforced, :unavailable (required but undeliverable), :skipped or :off.
  def self.admin_second_factor_state(email = nil)
    mode = ENV.fetch("ADMIN_SECOND_FACTOR", "auto").strip.downcase
    return :off if mode == "off"
    return :enforced if admin_code_deliverable?(email)
    mode == "required" ? :unavailable : :skipped
  end

  def self.admin_code_deliverable?(email)
    return !Rails.env.production? unless EmailDelivery.configured?
    email.blank? || (!EmailDelivery.reserved_address?(email) && !EmailSuppression.blocks_all?(email))
  end

  # Which warning explains a :skipped state for this admin address.
  def self.admin_second_factor_warning(email)
    return SECOND_FACTOR_SKIPPED_WARNING unless EmailDelivery.configured?
    EmailDelivery.reserved_address?(email) ? SECOND_FACTOR_ADDRESS_WARNING : SECOND_FACTOR_SUPPRESSED_WARNING
  end

  def register
    # Shared campus, office and mobile-carrier IPs sign up many real users; keep bulk abuse bounded.
    return unless throttle!("register", limit: 60, period: 1.hour)
    role = params[:role].to_s
    return render_error("Choose either a musician or hirer account.", :unprocessable_content, "INVALID_ROLE") unless %w[jobseeker employer].include?(role)

    return unless consent_acceptable?
    # The two-minute sign-up sends its answers with the account; the old payload has none.
    starter = Onboarding::Starter.from_params(params)
    unless starter.valid?(role)
      return render_error(starter.errors.values.flatten.to_sentence, :unprocessable_content, "VALIDATION_FAILED", fields: starter.errors)
    end

    # A vouch link (/join/musician?vouch=<token>) stamps the new account so the admin
    # verification queue can flag and sort it (see Vouch, Admin::VerificationsController#index).
    vouch = Vouch.find_by(token: params[:vouch], status: "invited") if params[:vouch].present?

    user, created = User.transaction do
      account = User.create!(name: params[:name], email: params[:email], password: params[:password], role:, status: :active,
        consented_at: consent_given? ? Time.current : nil, vouched_by_id: vouch&.voucher_id, password_set_at: Time.current)
      account.create_profile!
      vouch&.update!(status: "joined", vouchee_id: account.id)
      [account, starter.apply!(account)]
    end
    token = sign_in(user)
    verification_token = issue_token("verify_email", 24.hours, user)
    _verification_link, verification_delivery = deliver_token(verification_token, "/verify-email", user)
    audit!("auth.register", user, starter.any? ? { starter: created } : {})
    render json: { user: public_user(user), accessToken: token, realtime: Realtime.enabled?, verificationRequired: true, verificationDelivery: verification_delivery, starter: created }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render_error("An account already exists for this email.", :conflict)
  end

  def login
    unless password_login_enabled?
      return render_error("Password sign-in is turned off. Use an email sign-in code instead.", :forbidden, "PASSWORD_LOGIN_DISABLED")
    end
    email = normalized_email
    scopes = login_failure_scopes(email)
    return if failure_budget_exhausted?("login-failure", scopes, period: LOGIN_FAILURE_PERIOD)
    user = User.find_by(email:)
    unless user&.authenticate(params[:password])
      record_failure!("login-failure", scopes, period: LOGIN_FAILURE_PERIOD)
      if user && !user.password_set? && !user.admin? && user.synthetic_batch.nil?
        return render_error(PASSWORDLESS_LOGIN_MESSAGE, :unauthorized, "USE_CONNECTED_SIGN_IN") if user.auth_connections.any?
        return render_error(CODE_ONLY_LOGIN_MESSAGE, :unauthorized, "USE_EMAIL_CODE")
      end
      return render_error("Incorrect email or password.", :unauthorized)
    end
    return render_error("This account is not active.", :forbidden) unless user.active?
    # A password chosen before the mailbox was proven may be a stranger's (account pre-hijacking).
    return render_error(EMAIL_VERIFICATION_REQUIRED_MESSAGE, :forbidden, "EMAIL_VERIFICATION_REQUIRED") unless user.email_verified? || user.admin? || user.synthetic_batch.present?
    return unless admin_origin_allowed?(user)
    second_factor = user.admin? ? self.class.admin_second_factor_state(user.email) : nil
    return start_second_factor(user) if second_factor == :enforced
    if second_factor == :unavailable
      Rails.logger.error({ event: "admin_second_factor_unavailable", userId: user.id }.to_json)
      return render_error(SECOND_FACTOR_UNAVAILABLE_MESSAGE, :service_unavailable, "SECOND_FACTOR_UNAVAILABLE")
    end
    if second_factor == :skipped
      reason = if !EmailDelivery.configured? then "email_delivery_not_configured"
      elsif EmailDelivery.reserved_address?(user.email) then "email_address_undeliverable"
      else "email_suppressed"
      end
      Rails.logger.warn({ event: "admin_second_factor_skipped", userId: user.id, reason: }.to_json)
      audit!("auth.admin_second_factor_skipped", user, { reason:, ip: request.remote_ip })
    end

    user.update!(last_login_at: Time.current)
    token = sign_in(user)
    audit!("auth.login", user, second_factor ? { secondFactor: second_factor == :off ? "disabled" : "skipped" } : {})
    render json: { user: public_user(user), accessToken: token, realtime: Realtime.enabled? }
  end

  # POST /auth/second-factor {challengeToken, code} -> same shape as /auth/login.
  # Completes an admin password sign-in with the code emailed by the password step.
  def second_factor
    ip_scope = { ip: [request.remote_ip, SECOND_FACTOR_FAILURES_PER_IP] }
    return if failure_budget_exhausted?("second-factor-failure", ip_scope, period: SECOND_FACTOR_FAILURE_PERIOD)

    challenge = read_second_factor_challenge(params[:challengeToken])
    user = challenge && User.find_by(id: challenge["user"])
    code = user && SignInCode.find_by(id: challenge["code"], email: user.email)
    unless code
      record_failure!("second-factor-failure", ip_scope, period: SECOND_FACTOR_FAILURE_PERIOD)
      return render_error(SECOND_FACTOR_EXPIRED_MESSAGE, :unauthorized, "SECOND_FACTOR_EXPIRED")
    end

    return unless admin_origin_allowed?(user)
    scopes = ip_scope.merge(user: [user.id, SECOND_FACTOR_FAILURES_PER_USER])
    return if failure_budget_exhausted?("second-factor-failure", scopes, period: SECOND_FACTOR_FAILURE_PERIOD)
    unless consume_code(code, params[:code])
      record_failure!("second-factor-failure", scopes, period: SECOND_FACTOR_FAILURE_PERIOD)
      return render_error(OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID")
    end
    return render_error("This account is not active.", :forbidden) unless user.active?

    user.update!(last_login_at: Time.current)
    token = sign_in(user)
    audit!("auth.login", user, { method: "password", secondFactor: "email_code" })
    render json: { user: public_user(user), accessToken: token, realtime: Realtime.enabled? }
  end

  # POST /auth/otp/request {email, role?, name?}
  # Always answers with the same body, whether or not an account exists: an
  # existing account gets a sign-in code; an unknown address with name+role gets
  # a sign-up code (the account is created on verify); any other address gets an
  # unusable placeholder row so the work done per request is the same.
  # GET /auth/methods -> which sign-in paths work right now, so the sign-in page never
  # offers an emailed code (or a reset link) that cannot be delivered; also which third-party
  # providers are configured, and (when signed in) the caller's connected accounts.
  def sign_in_methods
    result = { signInCodes: sign_in_codes_available?, password: password_login_enabled?, emailDelivery: EmailDelivery.configured?,
      providers: { google: GoogleOauth.enabled?, whatsapp: WhatsappOtp.enabled? } }
    result[:connections] = current_user.auth_connections.order(:created_at).map(&:as_summary) if current_user
    render json: result
  end

  # POST /api/auth/exchange {code} -> same shape as /auth/login. Redeems the single-use,
  # 60-second code GoogleAuthController#callback minted (see AuthExchangeCode) for the
  # real session token — a full-page OAuth redirect can never carry that token itself.
  def exchange
    user = AuthExchangeCode.redeem!(params[:code])
    return render_error("This sign-in link has expired or was already used.", :unauthorized, "EXCHANGE_INVALID") unless user
    return render_error("This sign-in link has expired or was already used.", :unauthorized, "EXCHANGE_INVALID") if admin_code_only_sign_in_blocked?(user)
    return render_error("This account is not active.", :forbidden) unless user.active?
    token = sign_in(user)
    render json: { user: public_user(user), accessToken: token, realtime: Realtime.enabled? }
  end

  # POST /api/auth/connect-ticket (signed in) -> {ticket, expiresIn}. A single-use,
  # 5-minute ticket GoogleAuthController#start/#callback use to identify the linking
  # user for intent=connect, so the OAuth start URL never carries a bearer token either.
  def connect_ticket
    return unless authenticate!
    ticket = GoogleConnectTicket.issue!(current_user)
    render json: { ticket:, expiresIn: GoogleConnectTicket::TTL.to_i }
  end

  # DELETE /api/auth/connections/:id — the signed-in user disconnecting one of their own
  # third-party sign-in methods. Refused (422) when it is the only sign-in method they have
  # and they have never set a password (see User#password_set?).
  def destroy_connection
    return unless authenticate!
    connection = current_user.auth_connections.find_by(id: params[:id])
    return render_error("Not found", :not_found) unless connection
    if !current_user.password_set? && current_user.auth_connections.count <= 1
      return render_error("Set a password, or connect another sign-in method, before disconnecting your only one.",
        :unprocessable_content, "LAST_SIGN_IN_METHOD")
    end
    GoogleOauth.revoke(connection.access_token) if connection.provider == "google"
    connection.destroy!
    audit!("auth.connection_removed", current_user, { provider: connection.provider })
    render json: { ok: true }
  end

  # POST /api/auth/phone-otp/request {phone} — WhatsApp equivalent of /auth/otp/request.
  # Dark until WhatsappOtp.enabled?. Signed in: sends a code to prove control of `phone`
  # before it is added to the account (see #phone_otp_verify). Signed out: sends a code only
  # when `phone` already belongs to a user with a *verified* phone (a sign-in code) — a
  # phone is never linked to a new account, and an unverified stored phone is never a
  # sign-in method, so the response otherwise looks identical either way.
  def phone_otp_request
    return render_error(PHONE_OTP_UNAVAILABLE_MESSAGE, :service_unavailable, "OTP_UNAVAILABLE") unless WhatsappOtp.enabled?
    phone = normalized_phone
    return render_error("Enter a valid phone number.", :unprocessable_content, "INVALID_PHONE") unless phone

    scopes = { phone: [phone, OTP_REQUESTS_PER_EMAIL], ip: [request.remote_ip, OTP_REQUESTS_PER_IP] }
    return if failure_budget_exhausted?("phone-otp-request", scopes, period: OTP_REQUEST_PERIOD)
    record_failure!("phone-otp-request", scopes, period: OTP_REQUEST_PERIOD)

    signed_in_user = current_user
    signed_out_match = signed_in_user.nil? && User.where(phone:).where.not(phone_verified_at: nil).exists?
    _record, code = PhoneOtp.issue!(phone:)
    queue_phone_otp(phone:, code:) if signed_in_user || signed_out_match

    result = { ok: true, message: PHONE_OTP_REQUEST_MESSAGE, expiresIn: PhoneOtp::LIFETIME.to_i }
    result[:debugCode] = code unless Rails.env.production?
    render json: result
  end

  # POST /api/auth/phone-otp/verify {phone, code}. Signed in: attaches and verifies `phone`
  # on the current account. Signed out: signs in the user whose verified phone this is,
  # exactly like /auth/otp/verify.
  def phone_otp_verify
    phone = normalized_phone
    ip_scope = { ip: [request.remote_ip, OTP_VERIFY_FAILURES_PER_IP] }
    return if failure_budget_exhausted?("phone-otp-verify-failure", ip_scope, period: OTP_VERIFY_FAILURE_PERIOD)
    return render_error(PHONE_OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID") unless phone

    candidate = PhoneOtp.latest_usable_for(phone)
    matched = candidate && consume_code(candidate, params[:code])
    unless matched
      record_failure!("phone-otp-verify-failure", ip_scope, period: OTP_VERIFY_FAILURE_PERIOD)
      return render_error(PHONE_OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID")
    end

    if current_user
      return render_error("Another account already uses that number.", :conflict) if User.where.not(id: current_user.id).exists?(phone:)
      current_user.update!(phone:, phone_verified_at: Time.current)
      audit!("auth.phone_connected", current_user)
      return render json: { ok: true, user: public_user(current_user) }
    end

    user = User.where(phone:).where.not(phone_verified_at: nil).first
    return render_error(PHONE_OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID") unless user
    return render_error(PHONE_OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID") if admin_code_only_sign_in_blocked?(user)
    return render_error("This account is not active.", :forbidden) unless user.active?

    user.update!(last_login_at: Time.current)
    token = sign_in(user)
    audit!("auth.login", user, { method: "whatsapp_code" })
    render json: { user: public_user(user), accessToken: token, realtime: Realtime.enabled? }
  end

  def otp_request
    return render_error(OTP_UNAVAILABLE_MESSAGE, :service_unavailable, "OTP_UNAVAILABLE") unless sign_in_codes_available?
    email = normalized_email
    return render_error("Enter a valid email address.", :unprocessable_content, "INVALID_EMAIL") unless email.match?(URI::MailTo::EMAIL_REGEXP) && email.length <= 254
    sign_up = otp_sign_up_params
    return if performed?

    scopes = { email: [email, OTP_REQUESTS_PER_EMAIL], ip: [request.remote_ip, OTP_REQUESTS_PER_IP] }
    return if failure_budget_exhausted?("otp-request", scopes, period: OTP_REQUEST_PERIOD)
    record_failure!("otp-request", scopes, period: OTP_REQUEST_PERIOD)
    # A code sent to a hard-bounced or complaining address can never arrive: say so instead
    # of leaving the person waiting. Checked after the throttle so it cannot be probed quickly.
    return render_error(EMAIL_SUPPRESSED_MESSAGE, :unprocessable_content, "EMAIL_SUPPRESSED") if EmailSuppression.blocks_all?(email)

    user = User.find_by(email:)
    pending = user ? {} : sign_up.to_h
    record, code = SignInCode.issue!(email:, pending_name: pending[:name], pending_role: pending[:role],
      pending_consented_at: pending[:role] && consent_given? ? Time.current : nil)
    if (user || record.sign_up?) && !admin_code_only_sign_in_blocked?(user)
      queue_sign_in_code(user:, email:, code:)
    else
      record.update_columns(used_at: record.created_at)
    end

    result = { ok: true, message: OTP_REQUEST_MESSAGE, expiresIn: SignInCode::LIFETIME.to_i }
    # Local QA without an email provider only. Never in production, and the same
    # for every address (an unknown address gets an unusable code).
    result[:debugCode] = code if !Rails.env.production? && !EmailDelivery.configured?
    render json: result
  end

  # POST /auth/otp/verify {email, code} -> same shape as /auth/login.
  def otp_verify
    email = normalized_email
    ip_scope = { ip: [request.remote_ip, OTP_VERIFY_FAILURES_PER_IP] }
    return if failure_budget_exhausted?("otp-verify-failure", ip_scope, period: OTP_VERIFY_FAILURE_PERIOD)

    code = consume_sign_in_code(email, params[:code])
    unless code
      record_failure!("otp-verify-failure", ip_scope, period: OTP_VERIFY_FAILURE_PERIOD)
      return render_error(OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID")
    end

    user = User.find_by(email:)
    created = false
    if user.nil? && code.sign_up?
      user, created = create_user_from_code(code)
    end
    return render_error(OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID") unless user
    return render_error(OTP_INVALID_MESSAGE, :unauthorized, "OTP_INVALID") if admin_code_only_sign_in_blocked?(user)
    return render_error("This account is not active.", :forbidden) unless user.active?

    dropped = user.reclaim_unverified_credentials!
    user.update!(email_verified: true, last_login_at: Time.current)
    notify_password_removed(user) if dropped
    token = sign_in(user)
    audit!(created ? "auth.register" : "auth.login", user, { method: "email_code" })
    render json: { user: public_user(user), accessToken: token, realtime: Realtime.enabled? }
  end

  def logout
    raw = request.authorization.to_s.match(/^Bearer\s+(.+)$/i)&.captures&.first
    Session.find_by(token_digest: digest(raw))&.destroy!
    render json: { ok: true }
  end

  def me
    return unless authenticate!
    render json: { user: public_user(current_user).merge(verification_state(current_user)), realtime: Realtime.enabled? }
  end

  def request_verification
    return unless authenticate!
    return unless throttle!("email-verification", limit: 5, period: 1.hour)
    return render json: { ok: true, alreadyVerified: true } if current_user.email_verified?
    token = issue_token("verify_email", 24.hours)
    render json: token_response(token, "/verify-email", current_user)
  end

  # POST /auth/resend-verification {email}: signed out. Sends a fresh verification link to an
  # unverified account; the answer is identical for every address.
  def resend_verification
    return unless throttle!("resend-verification", limit: 10, period: 1.hour)

    email = normalized_email
    user = User.find_by(email:)
    if user && !user.email_verified? && user.active? && !user.admin?
      # Over the per-address budget nothing is sent but the answer is identical (no oracle).
      key_period = 1.hour
      count_key = failure_key("resend-verification", :email, email, key_period)
      if (Rails.cache.increment(count_key, 1, expires_in: key_period) || 1) <= 3
        deliver_token(issue_token("verify_email", 24.hours, user), "/verify-email", user)
      end
    end
    render json: { ok: true, message: "If that address has an unconfirmed account, a new link is on its way." }
  end

  def verify_email
    token = EmailToken.usable("verify_email").find_by(token_digest: digest(params[:token]))
    return render_error("Verification link is invalid or expired.", :bad_request, "TOKEN_INVALID") unless token
    token.with_lock do
      return render_error("Verification link is invalid or expired.", :bad_request, "TOKEN_INVALID") if token.used_at? || token.expires_at <= Time.current
      token.update!(used_at: Time.current)
      token.user.update!(email_verified: true)
    end
    render json: { ok: true }
  end

  def forgot_password
    return unless throttle!("password-reset", limit: 10, period: 1.hour)
    if (user = User.find_by(email: normalized_email)) && reset_email_allowed?(user)
      token = issue_token("reset_password", 2.hours, user)
      _link, delivery = deliver_token(token, "/reset-password", user)
      unless delivery[:queued]
        Rails.logger.warn({ event: "password_reset_email_skipped", userId: user.id, reason: delivery[:reason] }.to_json)
      end
    else
      Rails.logger.info({ event: "password_reset_unknown_account_or_capped" }.to_json)
    end
    render json: { ok: true, message: "If an account exists, password reset instructions have been sent." }
  end

  # While a reset link sent within this window is still usable, another request sends nothing new:
  # the owner already has a working link, and nobody can flood an inbox (at most one reset email
  # per account per window, whichever networks ask). The answer is the same either way (no oracle).
  RESET_RESEND_AFTER = 10.minutes

  RESET_TOKEN_INVALID_MESSAGE = "This link has expired or was already used. Request a new one.".freeze

  # GET /auth/reset-password/check?token= -> {valid, role?}
  # Lets the reset-password page tell an expired or already-used link apart from a bad
  # password *before* the person types a new one, and route "Sign in" to the right role.
  def check_reset_password_token
    token = find_usable_reset_token(params[:token])
    return render json: { valid: false } unless token
    render json: { valid: true, role: token.user.role }
  end

  def reset_password
    token = find_usable_reset_token(params[:token])
    return render_error(RESET_TOKEN_INVALID_MESSAGE, :bad_request, "TOKEN_INVALID") unless token
    user = token.user
    violation = PasswordStrength.violation(params[:password], email: user.email, name: user.name)
    return render_error("Password #{violation}", :bad_request, "PASSWORD_WEAK") if violation

    token.with_lock do
      return render_error(RESET_TOKEN_INVALID_MESSAGE, :bad_request, "TOKEN_INVALID") if token.used_at? || token.expires_at <= Time.current
      # Reaching the reset link proves the mailbox, so the address counts as confirmed from here on.
      # Anything attached before that proof (a linked Google identity, a phone) may be a stranger's
      # pre-hijack, so it is dropped first, exactly as a first proven sign-in would.
      user.reclaim_unverified_credentials!
      user.update!(password: params[:password], password_set_at: Time.current, email_verified: true)
      token.update!(used_at: Time.current)
      Session.revoke!(user.sessions)
      user.email_tokens.usable("reset_password").update_all(used_at: Time.current)
    end
    AuditLog.create!(actor: user, action: "auth.password_reset", entity_type: "User", entity_id: user.id)
    # An admin is never signed in by an emailed link alone: they sign in again with the new
    # password and the emailed second factor, on the admin site.
    return render json: { ok: true, signInRequired: true } if user.admin?

    accessToken = sign_in(user)
    render json: { ok: true, user: public_user(user), accessToken:, realtime: Realtime.enabled? }
  end

  private

  # Whether a verification request is waiting for review, and since when (the profile page's
  # "Pending review" state). Unverified accounts only: an approved account has nothing pending.
  def verification_state(user)
    pending = user.profile&.verified? ? nil : user.verification_requests.where(status: "pending").order(created_at: :desc).first
    { "verificationPending" => pending.present?, "verificationRequestedAt" => pending&.created_at }
  end

  def reset_email_allowed?(user)
    # With the admin lock on, admins never use email-only recovery (see admin_code_only_sign_in_blocked?).
    return false if admin_code_only_sign_in_blocked?(user)

    !user.email_tokens.usable("reset_password").where(created_at: RESET_RESEND_AFTER.ago..).exists?
  end

  def find_usable_reset_token(raw)
    return nil unless raw.is_a?(String) && raw.present?
    EmailToken.usable("reset_password").find_by(token_digest: digest(raw))
  end

  def sign_in(user)
    raw = SecureRandom.urlsafe_base64(48)
    Session.start!(user, token_digest: digest(raw), user_agent: request.user_agent)
    # The cap counts live sessions only: expired ones are inert and kept a few days for the
    # retention sweep (config/retention.yml), so they must never push out a live one.
    Session.revoke!(user.sessions.where(id: user.sessions.active.order(created_at: :desc).offset(MAX_LIVE_SESSIONS).select(:id)))
    raw
  end

  def issue_token(purpose, lifetime, user = current_user)
    raw = SecureRandom.urlsafe_base64(48)
    user.email_tokens.where(purpose:, used_at: nil).update_all(used_at: Time.current)
    user.email_tokens.create!(purpose:, token_digest: digest(raw), expires_at: lifetime.from_now)
    raw
  end

  def normalized_email = params[:email].to_s.strip.downcase

  # E.164; India (+91) is assumed for a 10-digit number with no country code, per the WP.
  def normalized_phone
    raw = params[:phone].to_s.strip.gsub(/[\s-]/, "")
    raw = "+91#{raw}" if raw.match?(/\A[6-9]\d{9}\z/)
    raw if raw.match?(/\A\+[1-9]\d{7,14}\z/)
  end

  # Sign-up consent (Terms and Privacy Policy). Older clients send no `consent` at all and keep
  # working; a client that asks and gets "no" is refused, so an account never starts without it.
  def consent_given? = ActiveModel::Type::Boolean.new.cast(params[:consent]) == true

  def consent_acceptable?
    return true if !params.key?(:consent) || consent_given?
    render_error("Agree to the Terms and Privacy Policy to create your account.", :unprocessable_content, "CONSENT_REQUIRED",
      fields: { consent: ["Agree to the Terms and Privacy Policy to continue."] })
    false
  end

  def password_login_enabled? = ENV.fetch("PASSWORD_LOGIN_ENABLED", "true").strip.downcase != "false"

  # Outside production a missing provider falls back to the on-screen debug code.
  def sign_in_codes_available? = EmailDelivery.configured? || !Rails.env.production?

  # Validated the same way whether or not the address has an account, so a
  # validation error never reveals account existence. Returns nil for sign-in.
  def otp_sign_up_params
    role = params[:role].to_s.strip
    name = params[:name].to_s.strip
    return nil if role.blank? && name.blank?
    unless SignInCode::SIGN_UP_ROLES.include?(role)
      render_error("Choose either a musician or hirer account.", :unprocessable_content, "INVALID_ROLE")
      return nil
    end
    unless name.length.between?(2, 120)
      render_error("Enter a name between 2 and 120 characters.", :unprocessable_content, "INVALID_NAME")
      return nil
    end
    return nil unless consent_acceptable?
    { name:, role: }
  end

  # The password was right; answer with a short-lived challenge instead of a
  # session and email the admin a code that completes it.
  def start_second_factor(user)
    scopes = { email: [user.email, SECOND_FACTOR_CHALLENGES_PER_EMAIL] }
    return if failure_budget_exhausted?("second-factor-challenge", scopes, period: SECOND_FACTOR_CHALLENGE_PERIOD)
    record_failure!("second-factor-challenge", scopes, period: SECOND_FACTOR_CHALLENGE_PERIOD)

    record, code = SignInCode.issue!(email: user.email)
    queue_sign_in_code(user:, email: user.email, code:)
    audit!("auth.second_factor_challenge", user, { ip: request.remote_ip })
    challenge = second_factor_verifier.generate({ "user" => user.id, "code" => record.id }, purpose: SECOND_FACTOR_PURPOSE, expires_in: SignInCode::LIFETIME)
    result = { secondFactorRequired: true, method: "email_code", challengeToken: challenge, message: SECOND_FACTOR_MESSAGE, expiresIn: SignInCode::LIFETIME.to_i }
    result[:debugCode] = code if !Rails.env.production? && !EmailDelivery.configured?
    render json: result, status: :accepted
  end

  def read_second_factor_challenge(token)
    return nil unless token.is_a?(String) && token.length <= 1024
    payload = second_factor_verifier.verified(token, purpose: SECOND_FACTOR_PURPOSE)
    payload if payload.is_a?(Hash)
  end

  def second_factor_verifier = Rails.application.message_verifier("admin-second-factor")

  def create_user_from_code(code)
    user = User.transaction do
      created = User.create!(name: code.pending_name, email: code.email, role: code.pending_role, status: :active,
        email_verified: true, password: SecureRandom.base58(32), consented_at: code.pending_consented_at)
      created.create_profile!
      created
    end
    [user, true]
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    # Registered by another path since the code was sent; the verifier still
    # proved control of the inbox, so sign in to that account.
    [User.find_by(email: code.email), false]
  end

  # Tells a person whose password was removed (see User#reclaim_unverified_credentials!) why.
  def notify_password_removed(user)
    AccountNotices.password_removed(user)
  end

  def queue_phone_otp(phone:, code:)
    WhatsappOtp.send_code(phone:, code:)
  rescue StandardError => error
    Rails.logger.error({ event: "whatsapp_otp_enqueue_failed", error: error.class.name }.to_json)
    ErrorReporter.capture(error, tags: { source: "whatsapp_otp_enqueue_failed" })
  end

  def queue_sign_in_code(user:, email:, code:)
    return unless EmailDelivery.configured?
    user ? EmailDeliveryJob.enqueue_code(template: "sign_in_code", code:, user:) : EmailDeliveryJob.enqueue_code(template: "sign_in_code", code:, email:)
  rescue StandardError => error
    # The response must not differ, so a queueing failure is only logged.
    Rails.logger.error({ event: "email_enqueue_failed", template: "sign_in_code", error: error.class.name }.to_json)
    ErrorReporter.capture(error, tags: { source: "email_enqueue_failed", template: "sign_in_code" })
  end

  # With ADMIN_ORIGIN set, an admin's password sign-in (and its second step) is only
  # accepted from the admin site. Checked after the password or challenge has been
  # verified, so a non-admin, or a wrong password, gets exactly the same answers as before.
  def admin_origin_allowed?(user)
    return true unless user.admin? && !AdminOrigin.allows?(request)
    audit!("auth.admin_wrong_origin", user, { ip: request.remote_ip, origin: request.origin.to_s.first(200) })
    Rails.logger.warn({ event: "admin_wrong_origin", userId: user.id }.to_json)
    render_error(ADMIN_USE_ADMIN_SITE_MESSAGE, :forbidden, "ADMIN_USE_ADMIN_SITE")
    false
  end

  # With ADMIN_ORIGIN set, an admin account never gets or accepts an email-only sign-in code:
  # admins always use password + code on the admin site. The request answers the same body
  # as for any address and the verify step the generic invalid-code error.
  def admin_code_only_sign_in_blocked?(user) = user.present? && user.admin? && AdminOrigin.locked?

  def login_failure_scopes(email)
    {
      email_ip: [email.presence && "#{email}|#{request.remote_ip}", LOGIN_FAILURES_PER_EMAIL_AND_IP],
      email: [email, LOGIN_FAILURES_PER_EMAIL],
      ip: [request.remote_ip, LOGIN_FAILURES_PER_IP]
    }
  end

  def token_response(token, path, user)
    link, delivery = deliver_token(token, path, user)
    result = { ok: true, delivery: }
    result[:debugLink] = link unless Rails.env.production?
    result
  end

  # Builds the link and queues delivery. The returned hash is the public
  # `delivery`/`verificationDelivery` contract: { queued: true } once a provider
  # job is enqueued, otherwise { queued: false, delivered: false, reason: }.
  def deliver_token(token, path, user)
    link = "#{frontend_url}#{path}?token=#{CGI.escape(token)}"
    template = path.include?("reset") ? "reset_password" : "verify_email"
    [link, queue_email(user, template, link)]
  end

  def queue_email(user, template, link)
    return { queued: false, delivered: false, reason: "Recipient unavailable" } if user&.email.blank?
    return { queued: false, delivered: false, reason: "Email provider not configured" } unless EmailDelivery.configured?
    return { queued: false, delivered: false, reason: "Email address suppressed" } if EmailSuppression.blocks_all?(user.email)
    EmailDeliveryJob.enqueue(user:, template:, link:)
    { queued: true }
  rescue StandardError => error
    # The account/token already exists; report the failure instead of a 500.
    Rails.logger.error({ event: "email_enqueue_failed", template:, error: error.class.name }.to_json)
    ErrorReporter.capture(error, tags: { source: "email_enqueue_failed", template: })
    { queued: false, delivered: false, reason: "delivery error" }
  end

  def frontend_url = FrontendUrl.base
end
