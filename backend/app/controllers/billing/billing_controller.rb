module Billing
  class BillingController < ApplicationController
    PLANS = {
      "free" => { code: "free", name: "Free", monthly: 0, trialDays: 0, activePosts: 1, seats: 1, shortlist: 20, bookings: 2 },
      "pro" => { code: "pro", name: "Pro", monthly: 2499, trialDays: 14, activePosts: 10, seats: 2, shortlist: 250, bookings: 20 },
      "studio" => { code: "studio", name: "Studio", monthly: 5999, trialDays: 14, activePosts: 50, seats: 8, shortlist: 2_000, bookings: 100 },
      "enterprise" => { code: "enterprise", name: "Enterprise", monthly: nil, trialDays: 0, activePosts: 9999, seats: 999, shortlist: 99999, bookings: 9999 }
    }.freeze

    # Razorpay subscription events -> local status (allowed by the subscriptions_status_valid check).
    # `subscription.authenticated` depends on the trial and is resolved per event.
    SUBSCRIPTION_EVENT_STATUS = {
      "subscription.authenticated" => "pending",
      "subscription.activated" => "active",
      "subscription.charged" => "active",
      "subscription.resumed" => "active",
      # Razorpay `pending`: a renewal charge failed and is being retried. No paid capacity while unpaid.
      "subscription.pending" => "past_due",
      "subscription.halted" => "past_due",
      "subscription.paused" => "past_due",
      "subscription.cancelled" => "cancelled",
      "subscription.completed" => "cancelled"
    }.freeze
    # A Razorpay subscription in any of these states is a live recurring mandate.
    PAID_MANDATE_STATUSES = %w[active trialing pending past_due].freeze

    def plans = render(json: { plans: PLANS.values })

    def subscription
      return unless authenticate!
      sub = current_subscription
      ended = sub ? nil : Subscription.where(user: current_user, status: "cancelled", provider: "razorpay").where.not(provider_subscription_id: nil).order(updated_at: :desc).first
      render json: { subscription: sub, plan: PLANS[effective_plan(sub)], purchasedPlan: PLANS[sub&.plan_code || "free"],
                     summary: billing_summary(sub || ended), history: billing_history, testMode: RazorpayConfig.test_mode? || !RazorpayConfig.key_present? }
    end

    def checkout
      return unless authenticate!("jobseeker", "employer")
      code = params[:planCode]; return render_error("Invalid plan", :bad_request) unless PLANS.key?(code) && code != "free"
      return render json: { salesAssisted: true, message: "Our team will contact you for Enterprise onboarding." } if code == "enterprise"
      return render_error("Live billing is not configured.", :service_unavailable) if RazorpayConfig.key_present? && !RazorpayConfig.usable?
      unless RazorpayConfig.key_present?
        return render_error("Live billing is not configured.", :service_unavailable) if Rails.env.production?
        trial_days = trial_days_for(code)
        sub = replace_subscription!(plan_code: code, provider: "internal", status: trial_days.positive? ? "trialing" : "active", trial_started_at: trial_days.positive? ? Time.current : nil, trial_ends_at: trial_days.positive? ? trial_days.days.from_now : nil)
        return render json: { subscription: sub, checkout: { mode: "mock" } }
      end
      plan_id = ENV["RAZORPAY_PLAN_#{code.upcase}"].presence or return render_error("Razorpay plan is not configured.", :service_unavailable)
      gateway = RazorpayGateway.new
      attempt = sub = provider_sub = blocked = nil
      current_user.with_lock do
        existing = Subscription.where(user: current_user, plan_code: code, status: %w[trialing pending], provider: "razorpay").where.not(provider_subscription_id: nil).order(created_at: :desc).first
        if existing
          return render json: { subscription: existing, checkout: razorpay_checkout(existing.provider_subscription_id) }
        end
        key = billing_idempotency_key("subscription_create")
        prior_attempt = BillingAttempt.find_by(idempotency_key: key)
        return render_attempt(prior_attempt) if prior_attempt
        blocked = checkout_blocker(code)
        unless blocked
          trial_days = trial_days_for(code)
          trial_ends_at = trial_days.positive? ? trial_days.days.from_now : nil
          sub = Subscription.create!(user: current_user, plan_code: code, provider: "razorpay", status: "pending", trial_started_at: nil, trial_ends_at:)
          attempt = BillingAttempt.create!(user: current_user, operation: "subscription_create", provider: "razorpay", idempotency_key: key, state: "pending", resource_type: "Subscription", resource_id: sub.id, request_payload: { plan_id:, start_at: trial_ends_at&.to_i, plan_code: code }, last_attempted_at: Time.current)
        end
      end
      return render_error(*blocked) if blocked
      provider_sub = gateway.create_subscription(plan_id:, start_at: sub.trial_ends_at&.to_i, notes: { user_id: current_user.id, plan_code: code, attempt_id: attempt.id })
      attempt.update!(provider_resource_id: provider_sub.fetch("id"), response_payload: provider_sub)
      Subscription.transaction do
        sub.update!(provider_subscription_id: provider_sub.fetch("id"))
        attempt.succeed!(provider_resource_id: provider_sub.fetch("id"), response_payload: provider_sub)
      end
      render json: { subscription: sub, checkout: razorpay_checkout(provider_sub.fetch("id")) }
    rescue RazorpayGateway::GatewayError => error
      attempt&.fail_from!(error)
      sub&.update!(status: "cancelled") unless error.ambiguous?
      begin
        RazorpayGateway.new.cancel_subscription(provider_sub["id"]) if provider_sub&.key?("id") && !error.ambiguous?
      rescue RazorpayGateway::GatewayError => cleanup_error
        Rails.logger.error("razorpay checkout cleanup failed: #{cleanup_error.class}")
      end
      render_error(error.ambiguous? ? "Billing provider outcome is pending reconciliation. Do not retry with a new request." : error.message, :bad_gateway)
    end

    # Pending (never authorised) mandates, trials and past-due plans are cancelled immediately at
    # Razorpay: nothing has been paid for, so there is no cycle to honour. An active paid plan is
    # cancelled at cycle end and keeps its access until `current_period_end`.
    def cancel
      return unless authenticate!
      sub = current_subscription or return render_error("No active subscription", :not_found)
      return render_error("Cancellation is already scheduled.", :conflict, "CANCELLATION_SCHEDULED") if sub.cancel_at_period_end && sub.status == "active"

      unauthorised = Subscription.where(user: current_user, provider: "razorpay", status: "pending").where.not(provider_subscription_id: nil).to_a
      needs_provider = unauthorised.any? || (sub.provider == "razorpay" && sub.provider_subscription_id.present?)
      return render_error("Live billing is not configured.", :service_unavailable) if needs_provider && !RazorpayConfig.usable?
      gateway = RazorpayGateway.new if needs_provider
      unauthorised.each do |pending|
        gateway.cancel_subscription(pending.provider_subscription_id, at_cycle_end: false)
        pending.update!(status: "cancelled")
      end
      outcome = "cancelled"
      if sub.status == "pending"
        sub.update!(status: "cancelled") if sub.provider != "razorpay" || sub.provider_subscription_id.blank?
      elsif sub.provider == "razorpay" && sub.provider_subscription_id.present?
        at_cycle_end = sub.status == "active"
        entity = gateway.cancel_subscription(sub.provider_subscription_id, at_cycle_end:)
        if at_cycle_end
          sub.update!(cancel_at_period_end: true)
          outcome = "scheduled"
        else
          sub.update!(cancel_at_period_end: true)
          sub.apply_provider_status!(new_status: "cancelled", event_at: Time.current, event_id: "cancel:#{sub.provider_subscription_id}") if entity.is_a?(Hash) && %w[cancelled completed].include?(entity["status"])
        end
      else
        sub.update!(cancel_at_period_end: true)
        outcome = "scheduled"
      end
      audit!("billing.cancel", sub, { outcome: })
      render json: { ok: true, outcome:, accessEndsAt: outcome == "scheduled" ? sub.current_period_end : nil }
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
      status = SUBSCRIPTION_EVENT_STATUS[payload["event"]]
      status = sub&.trial_ends_at&.future? ? "trialing" : "pending" if payload["event"] == "subscription.authenticated"
      Subscription.transaction do
        subscription_result = sub&.apply_provider_status!(new_status: status, event_at:, event_id:) if status
        sub&.update!(trial_started_at: event_at) if subscription_result == :applied && status == "trialing" && sub.trial_started_at.blank?
        sub&.apply_provider_period!(payload.dig("payload", "subscription", "entity") || {}) if status && subscription_result != :invalid_transition
        supersede_internal_subscriptions!(sub) if subscription_result == :applied && %w[trialing active].include?(status)
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
    def razorpay_checkout(subscription_id)
      { mode: "razorpay", keyId: RazorpayConfig.key_id, subscriptionId: subscription_id }.merge(RazorpayConfig.simulator? ? { simulator: true } : {})
    end

    def billing_summary(sub)
      return nil unless sub

      scheduled = sub.cancel_at_period_end && sub.status == "active"
      status = scheduled ? "cancelling" : sub.status
      next_charge = case sub.status
      when "trialing" then sub.trial_ends_at
      when "active" then scheduled ? nil : sub.current_period_end
      end
      access_ends = case sub.status
      when "trialing" then sub.trial_ends_at
      when "active" then scheduled ? sub.current_period_end : nil
      end
      { status:, planCode: sub.plan_code, planName: PLANS.dig(sub.plan_code, :name) || sub.plan_code, provider: sub.provider,
        trialEndsAt: sub.trial_ends_at, currentPeriodStart: sub.current_period_start, currentPeriodEnd: sub.current_period_end,
        nextChargeAt: next_charge, accessEndsAt: access_ends, cancelAtPeriodEnd: sub.cancel_at_period_end, monthlyAmount: PLANS.dig(sub.plan_code, :monthly) }
    end

    # Subscription charges recorded from signed webhooks (newest first). Amounts are Razorpay paise.
    def billing_history
      BillingEvent.where(user: current_user, event_type: %w[subscription.charged subscription.pending]).order(created_at: :desc).limit(50).filter_map do |event|
        payment = event.payload.is_a?(Hash) ? event.payload.dig("payload", "payment", "entity") : nil
        next unless payment.is_a?(Hash) && payment["id"].present?

        { paymentId: payment["id"], invoiceId: payment["invoice_id"], amount: payment["amount"].to_i / 100.0, currency: payment["currency"].to_s.upcase,
          status: payment["status"], at: payment["created_at"].present? ? Time.at(payment["created_at"].to_i).utc : event.created_at, event: event.event_type }
      end.uniq { _1[:paymentId] }
    end

    def trial_days_for(code)
      Subscription.where(user: current_user).where.not(plan_code: "free").exists? ? 0 : PLANS[code][:trialDays]
    end

    def billing_idempotency_key(operation)
      supplied = request.headers["Idempotency-Key"].to_s.strip
      token = supplied.present? ? supplied.first(180) : SecureRandom.uuid
      "#{current_user.id}:#{operation}:#{token}"
    end

    def render_attempt(attempt)
      resource = attempt.resource_type.safe_constantize&.find_by(id: attempt.resource_id)
      if attempt.state == "succeeded" && resource.is_a?(Subscription) && resource.provider_subscription_id.present?
        return render json: { subscription: resource, checkout: razorpay_checkout(resource.provider_subscription_id), idempotent: true }
      end
      render_error(attempt.state == "ambiguous" ? "Billing provider outcome is pending reconciliation. Do not retry with a new request." : "Billing request is already being processed.", :conflict)
    end

    def replace_subscription!(**attributes)
      Subscription.transaction do
        Subscription.where(user: current_user, status: %w[active trialing pending]).update_all(status: "cancelled", updated_at: Time.current)
        Subscription.create!(user: current_user, **attributes)
      end
    end

    def process_booking_payment(payload, event_at:, event_id:)
      case payload["event"]
      when "payment.captured", "payment.failed"
        entity = payload.dig("payload", "payment", "entity") || {}
        notes = entity["notes"].is_a?(Hash) ? entity["notes"] : {}
        payment = BookingPayment.find_by(id: notes["payment_id"]) if notes["payment_id"].present?
        provider_order_id = entity["order_id"]
        payment ||= BookingPayment.find_by(provider_order_id:) if provider_order_id.present?
        return [payment, :payment_not_found] unless payment&.provider == "razorpay"

        result = if payload["event"] == "payment.captured"
          payment.apply_capture!(entity:, event_at:, event_id:)
        else
          payment.apply_failure!(entity:, event_at:, event_id:)
        end
        Rails.logger.error("razorpay duplicate booking capture payment=#{payment.id} provider_payment=#{entity["id"]}") if result == :duplicate_capture
        [payment, result]
      when "refund.processed"
        refund = payload.dig("payload", "refund", "entity") || {}
        payment = BookingPayment.find_by(provider_payment_id: refund["payment_id"]) if refund["payment_id"].present?
        return [payment, :payment_not_found] unless payment&.provider == "razorpay"

        [payment, payment.apply_refund!(refund:, payment_entity: payload.dig("payload", "payment", "entity"), event_at:, event_id:)]
      else
        [nil, nil]
      end
    end

    # [message, status, code] when a new Razorpay subscription must not be created.
    def checkout_blocker(code)
      in_flight = BillingAttempt.where(user: current_user, operation: "subscription_create", state: "pending", provider_resource_id: nil)
        .where("created_at > ?", BillingAttempt::IN_FLIGHT_WINDOW.ago)
      return ["A checkout is already being prepared. Wait a moment and try again.", :conflict, "CHECKOUT_IN_PROGRESS"] if in_flight.exists?

      # Same-plan trialing/pending mandates were already resumed by the caller; anything left is a live mandate.
      mandate = Subscription.where(user: current_user, provider: "razorpay", status: PAID_MANDATE_STATUSES)
        .where.not(provider_subscription_id: nil).order(created_at: :desc).first
      return nil unless mandate
      return ["You are already subscribed to this plan.", :conflict, "ALREADY_SUBSCRIBED"] if mandate.plan_code == code

      name = PLANS.dig(mandate.plan_code, :name) || mandate.plan_code
      ["You already have a #{name} subscription (#{mandate.status}). Cancel your current plan first; you can switch once it has ended.", :conflict, "PLAN_CHANGE_REQUIRES_CANCELLATION"]
    end

    # A paid Razorpay subscription has just been authorised or activated: only now
    # retire local (mock or admin-granted) plans, never before the replacement is live.
    def supersede_internal_subscriptions!(sub)
      return unless sub&.provider == "razorpay"

      Subscription.where(user_id: sub.user_id, provider: "internal", status: %w[active trialing pending]).where.not(id: sub.id)
        .update_all(status: "cancelled", updated_at: Time.current)
    end

    def provider_event_time(payload)
      value = payload["created_at"]
      return Time.current if value.blank?
      return Time.at(value.to_i).utc if value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      Time.current
    end

    # A Razorpay subscription that never received a provider id cannot be authorised or paid
    # (its create failed or is awaiting reconciliation), so it is not shown as the current plan.
    def current_subscription
      Subscription.where(user: current_user, status: %w[active trialing pending past_due])
        .where.not(provider: "razorpay", status: "pending", provider_subscription_id: nil)
        .order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'trialing' THEN 1 WHEN 'past_due' THEN 2 ELSE 3 END"), created_at: :desc).first
    end
    def effective_plan(_sub = nil) = Entitlements.for(current_user).plan_code
  end
end
