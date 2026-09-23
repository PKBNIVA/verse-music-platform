class AuthController < ApplicationController
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
    return unless throttle!("login", limit: 20, period: 1.hour)
    user = User.find_by(email: params[:email].to_s.downcase)
    return render_error("Incorrect email or password.", :unauthorized) unless user&.authenticate(params[:password])
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
    render json: token_response(token, "/verify-email")
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
    if (user = User.find_by(email: params[:email].to_s.downcase))
      token = issue_token("reset_password", 2.hours, user)
      token_response(token, "/reset-password")
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
    user.sessions.where(id: user.sessions.order(created_at: :desc).offset(5).select(:id)).delete_all
    raw
  end

  def issue_token(purpose, lifetime, user = current_user)
    raw = SecureRandom.urlsafe_base64(48)
    user.email_tokens.where(purpose:, used_at: nil).update_all(used_at: Time.current)
    user.email_tokens.create!(purpose:, token_digest: digest(raw), expires_at: lifetime.from_now)
    raw
  end

  def token_response(token, path)
    user = current_user || User.find_by(email: params[:email].to_s.downcase)
    link, delivery = deliver_token(token, path, user)
    result = { ok: true, delivery: }
    result[:debugLink] = link unless Rails.env.production?
    result
  end

  def deliver_token(token, path, user)
    link = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}#{path}?token=#{CGI.escape(token)}"
    delivery = EmailDelivery.call(to: user&.email, template: path.include?("reset") ? "reset_password" : "verify_email", data: { link: })
    [link, delivery]
  end
end
