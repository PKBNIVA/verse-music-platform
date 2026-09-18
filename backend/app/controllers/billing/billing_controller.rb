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
      Subscription.where(user: current_user, status: %w[active trialing pending]).update_all(status: "cancelled", updated_at: Time.current)
      if ENV["RAZORPAY_KEY_ID"].blank?
        return render_error("Live billing is not configured.", :service_unavailable) if Rails.env.production?
        sub = Subscription.create!(user: current_user, plan_code: code, provider: "internal", status: "trialing", trial_started_at: Time.current, trial_ends_at: PLANS[code][:trialDays].days.from_now)
        return render json: { subscription: sub, checkout: { mode: "mock" } }
      end
      plan_id = ENV["RAZORPAY_PLAN_#{code.upcase}"].presence or return render_error("Razorpay plan is not configured.", :service_unavailable)
      provider_sub = RazorpayGateway.new.create_subscription(plan_id:, notes: { user_id: current_user.id, plan_code: code })
      sub = Subscription.create!(user: current_user, plan_code: code, provider: "razorpay", provider_subscription_id: provider_sub.fetch("id"), status: "pending")
      render json: { subscription: sub, checkout: { mode: "razorpay", keyId: ENV["RAZORPAY_KEY_ID"], subscriptionId: provider_sub.fetch("id") } }
    rescue RazorpayGateway::GatewayError => error
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
      expected = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_WEBHOOK_SECRET"), raw)
      return render_error("Invalid webhook signature", :unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Razorpay-Signature"].to_s)
      payload = JSON.parse(raw); event_id = request.headers["X-Razorpay-Event-Id"].presence || Digest::SHA256.hexdigest(raw)
      return render json: { ok: true, duplicate: true } if BillingEvent.exists?(provider: "razorpay", provider_event_id: event_id)
      provider_id = payload.dig("payload", "subscription", "entity", "id")
      sub = Subscription.find_by(provider_subscription_id: provider_id)
      status = { "subscription.activated" => "active", "subscription.charged" => "active", "subscription.pending" => "pending", "subscription.halted" => "past_due", "subscription.cancelled" => "cancelled" }[payload["event"]]
      Subscription.transaction do
        sub&.update!(status:) if status
        BillingEvent.create!(provider: "razorpay", provider_event_id: event_id, user: sub&.user, event_type: payload["event"], payload:, processed_at: Time.current)
      end
      render json: { ok: true }
    end

    private
    def current_subscription = Subscription.where(user: current_user, status: %w[active trialing pending past_due]).order(created_at: :desc).first
    def effective_plan(sub) = sub && %w[active trialing].include?(sub.status) && (!sub.trial_ends_at || sub.trial_ends_at.future?) ? sub.plan_code : "free"
  end
end
