module Dev
  # Browser/Playwright side of the local Razorpay simulator. Plays the part of checkout.js
  # (handler payloads with a server-computed HMAC signature) and of Razorpay's webhook sender.
  #
  # Only routed when RazorpaySimulator.enabled? (RAZORPAY_SIMULATOR=true, rzp_test_ key, not
  # production); the guard below repeats that check so the controller can never run in production.
  class RazorpaySimulatorController < ApplicationController
    before_action :require_simulator!
    before_action -> { authenticate! }

    # Simulated Checkout: outcome = success | fail | dismiss.
    def checkout
      outcome = params[:outcome].to_s
      return render_error("outcome must be success, fail or dismiss", :bad_request) unless %w[success fail dismiss].include?(outcome)

      result = if params[:subscriptionId].present?
        Subscription.find_by!(provider_subscription_id: params[:subscriptionId].to_s, user: current_user)
        simulator.checkout_subscription(params[:subscriptionId].to_s, outcome:)
      elsif params[:orderId].present?
        BookingPayment.find_by!(provider_order_id: params[:orderId].to_s, payer: current_user)
        simulator.checkout_order(params[:orderId].to_s, outcome:)
      else
        return render_error("subscriptionId or orderId is required", :bad_request)
      end
      render json: result.except(:events).merge(webhook_output(result[:events]))
    end

    # Razorpay-side lifecycle: activate | charge | pending | halt | pause | resume | cancel | complete.
    def subscription_lifecycle
      sub = Subscription.find_by!(provider_subscription_id: params[:id].to_s)
      return render_error("Not found", :not_found) unless current_user.admin? || sub.user_id == current_user.id

      events = simulator.advance_subscription(params[:id].to_s, params[:simulate].to_s)
      render json: { subscription: simulator.subscription(params[:id].to_s) }.merge(webhook_output(events))
    end

    # A refund issued from the Razorpay dashboard (full unless `amount` in paise is given).
    def refund
      payment = BookingPayment.includes(booking_request: :act).find_by!(provider_payment_id: params[:id].to_s)
      allowed = current_user.admin? || payment.payer_id == current_user.id || payment.booking_request.act.owner_id == current_user.id
      return render_error("Not found", :not_found) unless allowed

      events = simulator.refund_payment(params[:id].to_s, amount: params[:amount].presence&.to_i)
      render json: { payment: simulator.payment(params[:id].to_s) }.merge(webhook_output(events))
    end

    # Signs an arbitrary event payload (for duplicate / out-of-order delivery rehearsal).
    def webhook
      payload = params.require(:payload)
      payload = payload.respond_to?(:to_unsafe_h) ? payload.to_unsafe_h : payload
      render json: webhook_output([payload], event_id: params[:eventId].presence)
    end

    private

    def require_simulator!
      head :not_found unless !Rails.env.production? && RazorpaySimulator.enabled?
    end

    def simulator = RazorpaySimulator.instance

    # Delivers to this server's webhook endpoint unless deliverWebhooks=false (always returned
    # undelivered in the test environment, where there is no server to post to).
    def webhook_output(events, event_id: nil)
      signed = Array(events).map { RazorpaySimulator::Webhooks.signed(_1, event_id:) }
      deliver = !Rails.env.test? && ActiveModel::Type::Boolean.new.cast(params.fetch(:deliverWebhooks, true))
      return { webhooks: signed } unless deliver

      { deliveries: RazorpaySimulator::Webhooks.deliver(signed, "#{request.base_url}/api/billing/webhook/razorpay") }
    end

    rescue_from RazorpaySimulator::Error do |error|
      render json: { error: error.message, code: "SIMULATOR_REJECTED", provider: error.body }, status: :unprocessable_entity
    end
  end
end
