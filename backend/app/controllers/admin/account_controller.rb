module Admin
  # The signed-in admin's own account: which address the sign-in code goes to, changing that
  # address (proved by a code sent to the new one), and changing the password.
  #
  # Errors that mean "try again" answer 422/403 rather than 401: the web app treats a 401 as
  # a dead session and signs the admin out.
  class AccountController < BaseController
    include ConsumesSignInCodes
    include UserRateLimit

    EMAIL_CHANGE_PURPOSE = :admin_email_change
    EMAIL_CHANGE_REQUESTS_PER_HOUR = 5
    CONFIRM_FAILURES_PER_USER = 10
    PASSWORD_FAILURES_PER_USER = 10
    FAILURE_PERIOD = 15.minutes
    MIN_PASSWORD_LENGTH = 10
    EMAIL_CHANGE_MESSAGE = "We emailed a 6-digit code to the new address. Enter it here to finish the change. It expires in 10 minutes.".freeze
    EMAIL_CHANGE_EXPIRED_MESSAGE = "This email change has expired or was started by someone else. Start again.".freeze
    EMAIL_UNDELIVERABLE_MESSAGE = "That address can't receive mail (a reserved domain such as .local or .invalid). Use a real mailbox.".freeze
    EMAIL_TAKEN_MESSAGE = "Another account already uses that email address.".freeze
    EMAIL_UNCHANGED_MESSAGE = "That is already your email address.".freeze
    EMAIL_DELIVERY_REQUIRED_MESSAGE = "Changing the admin email needs an emailed code, but email delivery is not configured on the server.".freeze

    # GET /api/admin/account -> the signals behind the admin site's banner.
    def show
      render json: account_json(current_user)
    end

    # POST /api/admin/account/email/request {email} -> 202 {changeToken, expiresIn, message}
    # The code goes to the new address, so completing the change proves that mailbox works
    # before the admin's sign-in codes start going there.
    def request_email_change
      return unless within_user_rate_limit?("admin-email-change", limit: EMAIL_CHANGE_REQUESTS_PER_HOUR, period: 1.hour)
      email = params[:email].to_s.strip.downcase
      return render_error("Enter a valid email address.", :unprocessable_content, "INVALID_EMAIL") unless email.match?(URI::MailTo::EMAIL_REGEXP) && email.length <= 254
      return render_error(EMAIL_UNCHANGED_MESSAGE, :unprocessable_content, "EMAIL_UNCHANGED") if email == current_user.email
      return render_error(EMAIL_UNDELIVERABLE_MESSAGE, :unprocessable_content, "EMAIL_UNDELIVERABLE") if EmailDelivery.reserved_address?(email)
      return render_error(AuthController::EMAIL_SUPPRESSED_MESSAGE, :unprocessable_content, "EMAIL_SUPPRESSED") if EmailSuppression.blocks_all?(email)
      return render_error(EMAIL_TAKEN_MESSAGE, :conflict, "EMAIL_TAKEN") if User.where.not(id: current_user.id).exists?(email:)
      return render_error(EMAIL_DELIVERY_REQUIRED_MESSAGE, :service_unavailable, "EMAIL_DELIVERY_NOT_CONFIGURED") if Rails.env.production? && !EmailDelivery.configured?

      record, code = SignInCode.issue!(email:)
      EmailDeliveryJob.enqueue_code(template: "admin_email_change", code:, email:) if EmailDelivery.configured?
      audit!("admin.account.email_requested", current_user, { email: })
      token = email_change_verifier.generate({ "user" => current_user.id, "email" => email, "code" => record.id }, purpose: EMAIL_CHANGE_PURPOSE, expires_in: SignInCode::LIFETIME)
      result = { changeToken: token, expiresIn: SignInCode::LIFETIME.to_i, message: EMAIL_CHANGE_MESSAGE }
      # Local QA without an email provider only, never in production (same rule as sign-in codes).
      result[:debugCode] = code if !Rails.env.production? && !EmailDelivery.configured?
      render json: result, status: :accepted
    end

    # POST /api/admin/account/email/confirm {changeToken, code} -> {user}
    def confirm_email_change
      scopes = { user: [current_user.id, CONFIRM_FAILURES_PER_USER] }
      return if failure_budget_exhausted?("admin-email-confirm-failure", scopes, period: FAILURE_PERIOD)

      change = read_email_change(params[:changeToken])
      code = change && change["user"] == current_user.id && SignInCode.find_by(id: change["code"], email: change["email"])
      unless code
        record_failure!("admin-email-confirm-failure", scopes, period: FAILURE_PERIOD)
        return render_error(EMAIL_CHANGE_EXPIRED_MESSAGE, :unprocessable_content, "EMAIL_CHANGE_EXPIRED")
      end
      unless consume_code(code, params[:code])
        record_failure!("admin-email-confirm-failure", scopes, period: FAILURE_PERIOD)
        return render_error(AuthController::OTP_INVALID_MESSAGE, :unprocessable_content, "OTP_INVALID")
      end
      new_email = code.email
      return render_error(EMAIL_TAKEN_MESSAGE, :conflict, "EMAIL_TAKEN") if User.where.not(id: current_user.id).exists?(email: new_email)

      previous_email = current_user.email
      current_user.update!(email: new_email, email_verified: true)
      revoke_other_sessions!
      audit!("admin.account.email_changed", current_user, { from: previous_email, to: new_email })
      notify_previous_address(previous_email, new_email)
      render json: { user: public_user(current_user) }
    rescue ActiveRecord::RecordNotUnique
      render_error(EMAIL_TAKEN_MESSAGE, :conflict, "EMAIL_TAKEN")
    end

    # POST /api/admin/account/password {currentPassword, newPassword} -> {ok}
    def change_password
      scopes = { user: [current_user.id, PASSWORD_FAILURES_PER_USER] }
      return if failure_budget_exhausted?("admin-password-failure", scopes, period: FAILURE_PERIOD)
      unless current_user.authenticate(params[:currentPassword].to_s)
        record_failure!("admin-password-failure", scopes, period: FAILURE_PERIOD)
        return render_error("Your current password is incorrect.", :forbidden, "PASSWORD_INCORRECT")
      end
      new_password = params[:newPassword]
      return render_error("Password must be at least #{MIN_PASSWORD_LENGTH} characters.", :unprocessable_content, "PASSWORD_TOO_SHORT") unless new_password.is_a?(String) && new_password.length >= MIN_PASSWORD_LENGTH
      return render_error("Choose a password you have not used before.", :unprocessable_content, "PASSWORD_UNCHANGED") if current_user.authenticate(new_password)

      current_user.update!(password: new_password)
      current_user.email_tokens.usable("reset_password").update_all(used_at: Time.current)
      revoke_other_sessions!
      audit!("admin.account.password_changed", current_user, { ip: request.remote_ip })
      render json: { ok: true }
    end

    private

    def account_json(user)
      {
        email: user.email,
        emailDeliverable: !EmailDelivery.reserved_address?(user.email) && !EmailSuppression.blocks_all?(user.email),
        secondFactor: AuthController.admin_second_factor_state(user.email).to_s,
        adminOrigin: AdminOrigin.locked?
      }
    end

    # Every other browser holding this admin's token is signed out; the one making the change stays.
    def revoke_other_sessions!
      Session.revoke!(current_user.sessions.where.not(id: current_session.id))
    end

    def notify_previous_address(previous_email, new_email)
      return unless EmailDelivery.configured?
      return if EmailDelivery.reserved_address?(previous_email) || EmailSuppression.blocks_all?(previous_email)
      EmailDeliveryJob.enqueue_notice(template: "admin_email_changed", detail: new_email, email: previous_email)
    rescue StandardError => error
      # The change is done; a queueing failure is reported, not surfaced as a failed change.
      Rails.logger.error({ event: "email_enqueue_failed", template: "admin_email_changed", error: error.class.name }.to_json)
      ErrorReporter.capture(error, tags: { source: "email_enqueue_failed", template: "admin_email_changed" })
    end

    def read_email_change(token)
      return nil unless token.is_a?(String) && token.length <= 1024
      payload = email_change_verifier.verified(token, purpose: EMAIL_CHANGE_PURPOSE)
      payload if payload.is_a?(Hash)
    end

    def email_change_verifier = Rails.application.message_verifier("admin-email-change")
  end
end
