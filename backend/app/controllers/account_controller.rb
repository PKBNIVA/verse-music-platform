# The signed-in user's own account: name, email (proved by a code sent to the new
# address, mirroring Admin::AccountController's design for the admin site), password,
# a copy of their data, and account deletion (see AccountErasure for exactly what is
# removed and what is kept).
class AccountController < ApplicationController
  include ConsumesSignInCodes
  include UserRateLimit

  EXPORTS_PER_HOUR = 5
  DELETE_ATTEMPTS_PER_HOUR = 10
  EMAIL_CHANGE_PURPOSE = :account_email_change
  EMAIL_CHANGE_REQUESTS_PER_HOUR = 5
  CONFIRM_FAILURES_PER_USER = 10
  PASSWORD_FAILURES_PER_USER = 10
  FAILURE_PERIOD = 15.minutes
  EMAIL_CHANGE_MESSAGE = "We emailed a 6-digit code to the new address. Enter it here to finish the change. It expires in 10 minutes.".freeze
  EMAIL_CHANGE_EXPIRED_MESSAGE = "This email change has expired or was started by someone else. Start again.".freeze
  EMAIL_UNDELIVERABLE_MESSAGE = "That address can't receive mail (a reserved domain such as .local or .invalid). Use a real mailbox.".freeze
  EMAIL_TAKEN_MESSAGE = "Another account already uses that email address.".freeze
  EMAIL_UNCHANGED_MESSAGE = "That is already your email address.".freeze
  EMAIL_DELIVERY_REQUIRED_MESSAGE = "Changing your email needs an emailed code, but email delivery is not configured on the server.".freeze

  before_action -> { authenticate! }

  # GET /api/account/export
  def export
    return unless within_user_rate_limit?("account-export", limit: EXPORTS_PER_HOUR, period: 1.hour)

    export = AccountExport.new(current_user)
    audit!("account.export", current_user)
    response.set_header("Content-Disposition", ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: export.filename))
    response.set_header("Cache-Control", "no-store")
    render json: export
  end

  # PATCH /api/account/name {name}
  def update_name
    name = params[:name].to_s.strip
    unless name.length.between?(2, 120)
      return render_error("Enter a name between 2 and 120 characters.", :unprocessable_content, "INVALID_NAME")
    end
    current_user.update!(name:)
    audit!("account.name_changed", current_user)
    render json: { user: public_user(current_user) }
  end

  # POST /api/account/email/request {email} -> 202 {changeToken, expiresIn, message}
  # The code goes to the new address, so completing the change proves that mailbox
  # works before the account's future sign-in codes and notices start going there.
  def request_email_change
    return unless within_user_rate_limit?("account-email-change", limit: EMAIL_CHANGE_REQUESTS_PER_HOUR, period: 1.hour)
    email = params[:email].to_s.strip.downcase
    return render_error("Enter a valid email address.", :unprocessable_content, "INVALID_EMAIL") unless email.match?(URI::MailTo::EMAIL_REGEXP) && email.length <= 254
    return render_error(EMAIL_UNCHANGED_MESSAGE, :unprocessable_content, "EMAIL_UNCHANGED") if email == current_user.email
    return render_error(EMAIL_UNDELIVERABLE_MESSAGE, :unprocessable_content, "EMAIL_UNDELIVERABLE") if EmailDelivery.reserved_address?(email)
    return render_error(AuthController::EMAIL_SUPPRESSED_MESSAGE, :unprocessable_content, "EMAIL_SUPPRESSED") if EmailSuppression.blocks_all?(email)
    return render_error(EMAIL_TAKEN_MESSAGE, :conflict, "EMAIL_TAKEN") if User.where.not(id: current_user.id).exists?(email:)
    return render_error(EMAIL_DELIVERY_REQUIRED_MESSAGE, :service_unavailable, "EMAIL_DELIVERY_NOT_CONFIGURED") if Rails.env.production? && !EmailDelivery.configured?

    record, code = SignInCode.issue!(email:)
    EmailDeliveryJob.enqueue_code(template: "account_email_change", code:, email:) if EmailDelivery.configured?
    audit!("account.email_requested", current_user, { email: })
    token = email_change_verifier.generate({ "user" => current_user.id, "email" => email, "code" => record.id }, purpose: EMAIL_CHANGE_PURPOSE, expires_in: SignInCode::LIFETIME)
    result = { changeToken: token, expiresIn: SignInCode::LIFETIME.to_i, message: EMAIL_CHANGE_MESSAGE }
    result[:debugCode] = code if !Rails.env.production? && !EmailDelivery.configured?
    render json: result, status: :accepted
  end

  # POST /api/account/email/confirm {changeToken, code} -> {user}
  def confirm_email_change
    scopes = { user: [current_user.id, CONFIRM_FAILURES_PER_USER] }
    return if failure_budget_exhausted?("account-email-confirm-failure", scopes, period: FAILURE_PERIOD)

    change = read_email_change(params[:changeToken])
    code = change && change["user"] == current_user.id && SignInCode.find_by(id: change["code"], email: change["email"])
    unless code
      record_failure!("account-email-confirm-failure", scopes, period: FAILURE_PERIOD)
      return render_error(EMAIL_CHANGE_EXPIRED_MESSAGE, :unprocessable_content, "EMAIL_CHANGE_EXPIRED")
    end
    unless consume_code(code, params[:code])
      record_failure!("account-email-confirm-failure", scopes, period: FAILURE_PERIOD)
      return render_error(AuthController::OTP_INVALID_MESSAGE, :unprocessable_content, "OTP_INVALID")
    end
    new_email = code.email
    return render_error(EMAIL_TAKEN_MESSAGE, :conflict, "EMAIL_TAKEN") if User.where.not(id: current_user.id).exists?(email: new_email)

    previous_email = current_user.email
    current_user.update!(email: new_email, email_verified: true)
    revoke_other_sessions!
    audit!("account.email_changed", current_user, { from: previous_email, to: new_email })
    notify_previous_address(previous_email, new_email)
    render json: { user: public_user(current_user) }
  rescue ActiveRecord::RecordNotUnique
    render_error(EMAIL_TAKEN_MESSAGE, :conflict, "EMAIL_TAKEN")
  end

  # POST /api/account/password {currentPassword, newPassword} -> {ok}
  # An account that has never had a password of its own (it signs in with an emailed code or
  # Google) sets its first one here without a current password: the signed-in session is the proof.
  def change_password
    # Admins (seeded with a password but no password_set_at) always prove the current one.
    first_password = !current_user.password_set? && !current_user.admin?
    scopes = { user: [current_user.id, PASSWORD_FAILURES_PER_USER] }
    return if failure_budget_exhausted?("account-password-failure", scopes, period: FAILURE_PERIOD)
    unless first_password || current_user.authenticate(params[:currentPassword].to_s)
      record_failure!("account-password-failure", scopes, period: FAILURE_PERIOD)
      return render_error("Your current password is incorrect.", :forbidden, "PASSWORD_INCORRECT")
    end
    new_password = params[:newPassword]
    violation = new_password.is_a?(String) ? PasswordStrength.violation(new_password, email: current_user.email, name: current_user.name) : PasswordStrength::TOO_SHORT
    return render_error("Password #{violation}", :unprocessable_content, "PASSWORD_WEAK") if violation
    return render_error("Choose a password you have not used before.", :unprocessable_content, "PASSWORD_UNCHANGED") if current_user.authenticate(new_password)

    current_user.update!(password: new_password, password_set_at: Time.current)
    current_user.email_tokens.usable("reset_password").update_all(used_at: Time.current)
    # Adding a first password does not sign anyone out; changing an existing one does.
    revoke_other_sessions! unless first_password
    audit!(first_password ? "account.password_set" : "account.password_changed", current_user, { ip: request.remote_ip })
    notify_password_set if first_password
    render json: { ok: true, passwordSet: true }
  end

  # DELETE /api/account {confirmEmail}
  # The user types their own email address to confirm; this also stops a stray
  # request from an old tab deleting the account without the user seeing it.
  def destroy
    return unless within_user_rate_limit?("account-delete", limit: DELETE_ATTEMPTS_PER_HOUR, period: 1.hour)
    unless params[:confirmEmail].is_a?(String) && params[:confirmEmail].strip.casecmp?(current_user.email)
      return render_error("Type your account email exactly to confirm.", :unprocessable_content, "CONFIRMATION_MISMATCH")
    end

    erasure = AccountErasure.new(current_user)
    if (refusal = erasure.refusal)
      return render_error(refusal.message, :conflict, refusal.code)
    end

    audit!("account.delete", current_user)
    erasure.call!
    render json: { deleted: true }
  end

  private

  # Every other browser holding this account's token is signed out; the one making the
  # change stays (matches Admin::AccountController's behaviour for the admin's own account).
  def revoke_other_sessions!
    Session.revoke!(current_user.sessions.where.not(id: current_session.id))
  end

  # A new way into the account is a security event: tell the owner so they can act if it was not them.
  def notify_password_set
    email = current_user.email
    return unless EmailDelivery.configured?
    return if EmailDelivery.reserved_address?(email) || EmailSuppression.blocks_all?(email)
    EmailDeliveryJob.enqueue_notice(template: "account_password_set", detail: email, email:)
  rescue StandardError => error
    Rails.logger.error({ event: "email_enqueue_failed", template: "account_password_set", error: error.class.name }.to_json)
    ErrorReporter.capture(error, tags: { source: "email_enqueue_failed", template: "account_password_set" })
  end

  def notify_previous_address(previous_email, new_email)
    return unless EmailDelivery.configured?
    return if EmailDelivery.reserved_address?(previous_email) || EmailSuppression.blocks_all?(previous_email)
    EmailDeliveryJob.enqueue_notice(template: "account_email_changed", detail: new_email, email: previous_email)
  rescue StandardError => error
    Rails.logger.error({ event: "email_enqueue_failed", template: "account_email_changed", error: error.class.name }.to_json)
    ErrorReporter.capture(error, tags: { source: "email_enqueue_failed", template: "account_email_changed" })
  end

  def read_email_change(token)
    return nil unless token.is_a?(String) && token.length <= 1024
    payload = email_change_verifier.verified(token, purpose: EMAIL_CHANGE_PURPOSE)
    payload if payload.is_a?(Hash)
  end

  def email_change_verifier = Rails.application.message_verifier("account-email-change")
end
