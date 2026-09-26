class AuthController < ApplicationController
  LOGIN_FAILURE_PERIOD = 15.minutes
  # Strict budget per (email, IP) pair; a looser global per-email budget still
  # stops distributed guessing without letting one attacker lock a user out.
  LOGIN_FAILURES_PER_EMAIL_AND_IP = 10
  LOGIN_FAILURES_PER_EMAIL = 100
  LOGIN_FAILURES_PER_IP = 50
  MAX_LIVE_SESSIONS = 10
  PRODUCTION_FRONTEND_URL = "https://verse-music-platform.vercel.app".freeze

  def register
    return unless throttle!("register", limit: 20, period: 1.hour)
    role = params[:role].to_s
    return render_error("Choose either a jobseeker or employer account.", :unprocessable_entity, "INVALID_ROLE") unless %w[jobseeker employer].include?(role)

    user = User.create!(name: params[:name], email: params[:email], password: params[:password], role:, status: :active)
    user.create_profile!
    token = sign_in(user)
    verification_token = issue_token("verify_email", 24.hours, user)
    _verification_link, verification_delivery = deliver_token(verification_token, "/verify-email", user)
    audit!("auth.register", user)
    render json: { user: public_user(user), accessToken: token, verificationRequired: true, verificationDelivery: verification_delivery }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render_error("An account already exists for this email.", :conflict)
  end

  def login
    email = normalized_email
    scopes = login_failure_scopes(email)
    return if failure_budget_exhausted?("login-failure", scopes, period: LOGIN_FAILURE_PERIOD)
    user = User.find_by(email:)
    unless user&.authenticate(params[:password])
      record_failure!("login-failure", scopes, period: LOGIN_FAILURE_PERIOD)
      return render_error("Incorrect email or password.", :unauthorized)
    end
    return render_error("This account is not active.", :forbidden) unless user.active?
    user.update!(last_login_at: Time.current)
    token = sign_in(user)
    audit!("auth.login", user)
    render json: { user: public_user(user), accessToken: token }
  end

  def logout
    raw = request.authorization.to_s.match(/^Bearer\s+(.+)$/i)&.captures&.first
    Session.find_by(token_digest: digest(raw))&.destroy!
    render json: { ok: true }
  end

  def me
    return unless authenticate!
    render json: { user: public_user(current_user) }
  end

  def request_verification
    return unless authenticate!
    return unless throttle!("email-verification", limit: 5, period: 1.hour)
    return render json: { ok: true, alreadyVerified: true } if current_user.email_verified?
    token = issue_token("verify_email", 24.hours)
    render json: token_response(token, "/verify-email", current_user)
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
    if (user = User.find_by(email: normalized_email))
      token = issue_token("reset_password", 2.hours, user)
      _link, delivery = deliver_token(token, "/reset-password", user)
      unless delivery[:queued]
        Rails.logger.warn({ event: "password_reset_email_skipped", userId: user.id, reason: delivery[:reason] }.to_json)
      end
    else
      Rails.logger.info({ event: "password_reset_unknown_account" }.to_json)
    end
    render json: { ok: true, message: "If an account exists, password reset instructions have been sent." }
  end

  def reset_password
    return render_error("Password must be at least 10 characters.", :bad_request) if params[:password].to_s.length < 10
    token = EmailToken.usable("reset_password").find_by(token_digest: digest(params[:token]))
    return render_error("Reset link is invalid or expired.", :bad_request, "TOKEN_INVALID") unless token
    token.with_lock do
      return render_error("Reset link is invalid or expired.", :bad_request, "TOKEN_INVALID") if token.used_at? || token.expires_at <= Time.current
      token.user.update!(password: params[:password])
      token.update!(used_at: Time.current)
      token.user.sessions.delete_all
      token.user.email_tokens.usable("reset_password").update_all(used_at: Time.current)
    end
    render json: { ok: true }
  end

  private

  def sign_in(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: digest(raw), expires_at: 30.days.from_now)
    user.sessions.where(id: user.sessions.order(created_at: :desc).offset(MAX_LIVE_SESSIONS).select(:id)).delete_all
    raw
  end

  def issue_token(purpose, lifetime, user = current_user)
    raw = SecureRandom.urlsafe_base64(48)
    user.email_tokens.where(purpose:, used_at: nil).update_all(used_at: Time.current)
    user.email_tokens.create!(purpose:, token_digest: digest(raw), expires_at: lifetime.from_now)
    raw
  end

  def normalized_email = params[:email].to_s.strip.downcase

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
    EmailDeliveryJob.enqueue(user:, template:, link:)
    { queued: true }
  rescue StandardError => error
    # The account/token already exists; report the failure instead of a 500.
    Rails.logger.error({ event: "email_enqueue_failed", template:, error: error.class.name }.to_json)
    { queued: false, delivered: false, reason: "delivery error" }
  end

  def frontend_url
    configured = ENV["FRONTEND_URL"].to_s.strip.sub(%r{/+\z}, "")
    return configured if configured.present?
    return "http://localhost:5173" unless Rails.env.production?

    Rails.logger.error({ event: "frontend_url_missing", fallback: PRODUCTION_FRONTEND_URL }.to_json)
    PRODUCTION_FRONTEND_URL
  end
end
