class AuthController < ApplicationController
  def register
    user = User.create!(name: params[:name], email: params[:email], password: params[:password], role: params[:role], status: :active)
    user.create_profile!
    sign_in(user)
    audit!("auth.register", user)
    render json: { user: public_user(user) }, status: :created
  rescue ActiveRecord::RecordNotUnique
    render_error("An account already exists for this email.", :conflict)
  end

  def login
    user = User.find_by(email: params[:email].to_s.downcase)
    return render_error("Incorrect email or password.", :unauthorized) unless user&.authenticate(params[:password])
    return render_error("This account is not active.", :forbidden) unless user.active?
    user.update!(last_login_at: Time.current)
    sign_in(user)
    audit!("auth.login", user)
    render json: { user: public_user(user) }
  end

  def logout
    Session.find_by(token_digest: digest(cookies.encrypted[:verse_session]))&.destroy!
    cookies.delete(:verse_session)
    render json: { ok: true }
  end

  def me
    return unless authenticate!
    render json: { user: public_user(current_user) }
  end

  def request_verification
    return unless authenticate!
    return render json: { ok: true, alreadyVerified: true } if current_user.email_verified?
    token = issue_token("verify_email", 24.hours)
    render json: token_response(token, "/verify-email")
  end

  def verify_email
    token = EmailToken.usable("verify_email").find_by(token_digest: digest(params[:token]))
    return render_error("Verification link is invalid or expired.", :bad_request, "TOKEN_INVALID") unless token
    token.transaction { token.update!(used_at: Time.current); token.user.update!(email_verified: true) }
    render json: { ok: true }
  end

  def forgot_password
    if (user = User.find_by(email: params[:email].to_s.downcase))
      token = issue_token("reset_password", 2.hours, user)
      return render json: token_response(token, "/reset-password")
    end
    render json: { ok: true }
  end

  def reset_password
    return render_error("Password must be at least 10 characters.", :bad_request) if params[:password].to_s.length < 10
    token = EmailToken.usable("reset_password").find_by(token_digest: digest(params[:token]))
    return render_error("Reset link is invalid or expired.", :bad_request, "TOKEN_INVALID") unless token
    token.transaction { token.user.update!(password: params[:password]); token.update!(used_at: Time.current); token.user.sessions.delete_all }
    render json: { ok: true }
  end

  private

  def sign_in(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: digest(raw), expires_at: 30.days.from_now)
    cookies.encrypted[:verse_session] = { value: raw, expires: 30.days.from_now, httponly: true, secure: Rails.env.production?, same_site: Rails.env.production? ? :none : :lax }
  end

  def issue_token(purpose, lifetime, user = current_user)
    raw = SecureRandom.urlsafe_base64(48)
    user.email_tokens.create!(purpose:, token_digest: digest(raw), expires_at: lifetime.from_now)
    raw
  end

  def token_response(token, path)
    result = { ok: true, delivery: { queued: false, provider: "not_configured" } }
    result[:debugLink] = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:5173')}#{path}?token=#{CGI.escape(token)}" unless Rails.env.production?
    result
  end
end
