module Billing
  class BillingController < ApplicationController
    PLANS = {
      "free" => { code: "free", name: "Free", monthly: 0, trialDays: 0, activePosts: 1, seats: 1, shortlist: 20, bookings: 2 },
      "pro" => { code: "pro", name: "Pro", monthly: 999, trialDays: 14, activePosts: 10, seats: 2, shortlist: 250, bookings: 20 },
      "studio" => { code: "studio", name: "Studio", monthly: 2999, trialDays: 14, activePosts: 50, seats: 8, shortlist: 2_000, bookings: 100 },
      "enterprise" => { code: "enterprise", name: "Enterprise", monthly: nil, trialDays: 0, activePosts: 9999, seats: 999, shortlist: 99999, bookings: 9999 }
    }.freeze

    def plans = render(json: { plans: PLANS.values })

    def subscription
      return unless authenticate!
      sub = current_subscription
      render json: { subscription: sub, plan: PLANS[effective_plan(sub)], purchasedPlan: PLANS[sub&.plan_code || "free"] }
    end

    def checkout
      return unless authenticate!("jobseeker", "employer")
      code = params[:planCode]; return render_error("Invalid plan", :bad_request) unless PLANS.key?(code) && code != "free"
      return render json: { salesAssisted: true, message: "Our team will contact you for Enterprise onboarding." } if code == "enterprise"
      if ENV["RAZORPAY_KEY_ID"].blank?
        return render_error("Live billing is not configured.", :service_unavailable) if Rails.env.production?
        trial_days = trial_days_for(code)
        sub = replace_subscription!(plan_code: code, provider: "internal", status: trial_days.positive? ? "trialing" : "active", trial_started_at: trial_days.positive? ? Time.current : nil, trial_ends_at: trial_days.positive? ? trial_days.days.from_now : nil)
        return render json: { subscription: sub, checkout: { mode: "mock" } }
      end
      plan_id = ENV["RAZORPAY_PLAN_#{code.upcase}"].presence or return render_error("Razorpay plan is not configured.", :service_unavailable)
      trial_days = trial_days_for(code)
      trial_ends_at = trial_days.positive? ? trial_days.days.from_now : nil
      gateway = RazorpayGateway.new
      current_user.with_lock do
        existing = Subscription.where(user: current_user, plan_code: code, status: %w[trialing pending], provider: "razorpay").where.not(provider_subscription_id: nil).order(created_at: :desc).first
        if existing
          return render json: { subscription: existing, checkout: { mode: "razorpay", keyId: ENV["RAZORPAY_KEY_ID"], subscriptionId: existing.provider_subscription_id } }
        end
        previous_provider_ids = Subscription.where(user: current_user, status: %w[active trialing pending], provider: "razorpay").where.not(provider_subscription_id: nil).pluck(:provider_subscription_id)
        provider_sub = gateway.create_subscription(plan_id:, start_at: trial_ends_at&.to_i, notes: { user_id: current_user.id, plan_code: code })
        sub = replace_subscription!(plan_code: code, provider: "razorpay", provider_subscription_id: provider_sub.fetch("id"), status: trial_days.positive? ? "trialing" : "pending", trial_started_at: trial_days.positive? ? Time.current : nil, trial_ends_at:)
      end
      previous_provider_ids.each do |provider_id|
        gateway.cancel_subscription(provider_id)
      rescue RazorpayGateway::GatewayError => cancellation_error
        Rails.logger.error("razorpay previous subscription cancellation failed: #{cancellation_error.class} subscription=#{provider_id}")
      end
      render json: { subscription: sub, checkout: { mode: "razorpay", keyId: ENV["RAZORPAY_KEY_ID"], subscriptionId: provider_sub.fetch("id") } }
    rescue RazorpayGateway::GatewayError => error
      begin
        RazorpayGateway.new.cancel_subscription(provider_sub["id"]) if provider_sub&.key?("id")
      rescue RazorpayGateway::GatewayError => cleanup_error
        Rails.logger.error("razorpay checkout cleanup failed: #{cleanup_error.class}")
      end
      render_error(error.message, :bad_gateway)
    end

    def cancel
      return unless authenticate!
      sub = current_subscription or return render_error("No active subscription", :not_found)
      RazorpayGateway.new.cancel_subscription(sub.provider_subscription_id) if sub.provider == "razorpay" && sub.provider_subscription_id.present?
      sub.update!(cancel_at_period_end: true)
      render json: { ok: true }
    rescue RazorpayGateway::GatewayError => error
      render_error(error.message, :bad_gateway)
    end

    def razorpay_webhook
      raw = request.raw_post
      secret = ENV["RAZORPAY_WEBHOOK_SECRET"].presence
      return render_error("Billing webhook is not configured", :service_unavailable) unless secret
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, raw)
      return render_error("Invalid webhook signature", :unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Razorpay-Signature"].to_s)
      payload = JSON.parse(raw); event_id = request.headers["X-Razorpay-Event-Id"].presence || Digest::SHA256.hexdigest(raw)
      return render json: { ok: true, duplicate: true } if BillingEvent.exists?(provider: "razorpay", provider_event_id: event_id)
      event_at = provider_event_time(payload)
      provider_id = payload.dig("payload", "subscription", "entity", "id")
      sub = Subscription.find_by(provider_subscription_id: provider_id)
      status = { "subscription.authenticated" => (sub&.trial_ends_at&.future? ? "trialing" : "pending"), "subscription.activated" => "active", "subscription.charged" => "active", "subscription.pending" => "pending", "subscription.halted" => "past_due", "subscription.cancelled" => "cancelled" }[payload["event"]]
      Subscription.transaction do
        subscription_result = sub&.apply_provider_status!(new_status: status, event_at:, event_id:) if status
        payment, payment_result = process_booking_payment(payload, event_at:, event_id:)
        result = subscription_result || payment_result || (status ? :subscription_not_found : :ignored)
        BillingEvent.create!(provider: "razorpay", provider_event_id: event_id, user: sub&.user || payment&.payer, event_type: payload["event"], payload:, processing_result: result, processed_at: Time.current)
      end
      render json: { ok: true }
    rescue JSON::ParserError
      render_error("Invalid webhook payload", :bad_request)
    rescue ActiveRecord::RecordNotUnique
      raise unless event_id && BillingEvent.exists?(provider: "razorpay", provider_event_id: event_id)

      render json: { ok: true, duplicate: true }
    end

    private
    def trial_days_for(code)
      Subscription.where(user: current_user).where.not(plan_code: "free").exists? ? 0 : PLANS[code][:trialDays]
    end

    def replace_subscription!(**attributes)
      Subscription.transaction do
        Subscription.where(user: current_user, status: %w[active trialing pending]).update_all(status: "cancelled", updated_at: Time.current)
        Subscription.create!(user: current_user, **attributes)
      end
    end

    def process_booking_payment(payload, event_at:, event_id:)
      return [nil, nil] unless payload["event"] == "payment.captured"
      entity = payload.dig("payload", "payment", "entity") || {}
      notes = entity["notes"] || {}
      payment = BookingPayment.find_by(id: notes["payment_id"])
      provider_order_id = entity["order_id"]
      payment ||= BookingPayment.find_by(provider_order_id:) if provider_order_id.present?
      return [payment, :payment_not_found] unless payment&.provider == "razorpay"

      [payment, payment.apply_capture!(entity:, event_at:, event_id:)]
    end

    def provider_event_time(payload)
      value = payload["created_at"]
      return Time.current if value.blank?
      return Time.at(value.to_i).utc if value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      Time.current
    end

    def current_subscription = Subscription.where(user: current_user, status: %w[active trialing pending past_due]).order(created_at: :desc).first
    def effective_plan(sub) = sub && %w[active trialing].include?(sub.status) && (!sub.trial_ends_at || sub.trial_ends_at.future?) ? sub.plan_code : "free"
  end
end
