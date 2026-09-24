class BookingsController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }

  def index
    scope = BookingRequest.joins(:act).includes(:requester, act: :owner, booking_quotes: [], booking_payments: [])
      .where("booking_requests.requester_id = ? OR acts.owner_id = ?", current_user.id, current_user.id).order(updated_at: :desc)
    render json: { bookings: scope.map { booking_json(_1) } }
  end

  def create
    act = Act.where(status: "active").find(params[:actId])
    return render_error("You cannot book your own act.", :conflict) if act.owner_id == current_user.id
    BookingRequest.transaction do
      booking = BookingRequest.create!(act:, requester: current_user, event_type: params[:eventType], event_name: params[:eventName], event_date: params[:eventDate], start_time: params[:startTime], duration_minutes: params[:durationMinutes], venue_name: params[:venueName], venue_address: params[:venueAddress], city: params[:city], audience_size: params[:audienceSize], indoor_outdoor: params[:indoorOutdoor], budget_min: params[:budgetMin], budget_max: params[:budgetMax], currency: params[:currency].presence || "INR", requirements: params[:requirements], production_provided: params[:productionProvided] || [], travel_provided: params[:travelProvided] || false, accommodation_provided: params[:accommodationProvided] || false, status: "requested")
      Notification.create!(user: act.owner, kind: "booking", title: "New booking enquiry", body: "#{current_user.name} enquired about #{act.name}.", link: "/bookings")
      audit!("booking.create", booking)
    end
    render json: { id: booking.id }, status: :created
  end

  def quote
    booking = owned_booking
    booking.with_lock do
      raise BookingRequest::InvalidTransition unless %w[requested viewed negotiating quoted].include?(booking.status)
      quote = booking.booking_quotes.create!(created_by: current_user, performance_fee: params[:performanceFee], travel_fee: params[:travelFee] || 0, production_fee: params[:productionFee] || 0, other_fee: params[:otherFee] || 0, currency: params[:currency].presence || booking.currency, deposit_percent: params[:depositPercent] || 50, valid_until: params[:validUntil], inclusions: params[:inclusions], exclusions: params[:exclusions], cancellation_terms: params[:cancellationTerms], status: "sent")
      booking.update!(status: "quoted")
      Notification.create!(user: booking.requester, kind: "booking_quote", title: "Booking quote received", body: "Quote received for #{booking.act.name}.", link: "/bookings")
    end
    render json: { id: quote.id, total: quote.total }, status: :created
  rescue BookingRequest::InvalidTransition
    render_error("This booking can no longer be quoted.", :conflict)
  end

  def change_status
    booking = BookingRequest.includes(:act).find(params[:id])
    booking.transition_to!(params[:status], actor: current_user)
    render json: { ok: true }
  rescue BookingRequest::InvalidTransition
    render_error("Invalid booking status change.", :conflict)
  end

  def payment_order
    booking = BookingRequest.includes(:booking_quotes).find(params[:id])
    return render_error("Booking not found", :not_found) unless booking.requester_id == current_user.id
    return render_error("Live payments are not configured.", :service_unavailable) if Rails.env.production? && ENV.values_at("RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET").any?(&:blank?)
    payment = existing = quote = nil
    payment_error = nil
    booking.with_lock do
      payment_error = ["Booking must be accepted before payment.", :conflict] unless booking.status == "accepted"
      quote = booking.booking_quotes.where(status: %w[sent accepted]).order(created_at: :desc).first unless payment_error
      payment_error = ["No active quote", :conflict] if !payment_error && !quote
      payment_error = ["This quote has expired.", :conflict] if !payment_error && quote.valid_until.present? && quote.valid_until <= Time.current
      existing = booking.booking_payments.where(kind: "deposit", status: %w[created paid]).order(created_at: :desc).first unless payment_error
      unless payment_error || existing
        amount = (quote.total * quote.deposit_percent / 100.0).round
        payment_error = ["Deposit amount must be greater than zero.", :unprocessable_entity] unless amount.positive?
        payment = booking.booking_payments.create!(booking_quote: quote, payer: current_user, kind: "deposit", amount:, currency: quote.currency.to_s.upcase, provider: ENV["RAZORPAY_KEY_ID"].present? ? "razorpay" : "internal", status: "created") unless payment_error
      end
    end
    return render_error(*payment_error) if payment_error
    if existing
      return render_error("Deposit is already paid.", :conflict) if existing.status == "paid"
      return render_error("Payment order is being prepared. Retry shortly.", :conflict) if existing.provider == "razorpay" && existing.provider_order_id.blank?
      checkout = existing.provider == "razorpay" ? { mode: "razorpay", keyId: ENV["RAZORPAY_KEY_ID"], amount: existing.amount * 100, currency: existing.currency, orderId: existing.provider_order_id } : { mode: "mock" }
      return render json: { payment: existing, checkout: }
    end
    checkout = if payment.provider == "razorpay"
      order = RazorpayGateway.new.create_order(amount_paise: payment.amount * 100, currency: quote.currency, receipt: "booking-#{payment.id}", notes: { booking_id: booking.id, payment_id: payment.id })
      payment.update!(provider_order_id: order.fetch("id"))
      { mode: "razorpay", keyId: ENV["RAZORPAY_KEY_ID"], amount: order.fetch("amount"), currency: order.fetch("currency"), orderId: order.fetch("id") }
    else
      { mode: "mock" }
    end
    render json: { payment:, checkout: }
  rescue RazorpayGateway::GatewayError => error
    payment&.update!(status: "failed")
    render_error(error.message, :bad_gateway)
  rescue ActiveRecord::RecordNotUnique
    render_error("A payment order already exists. Retry shortly.", :conflict)
  end

  def confirm_payment
    payment = BookingPayment.find(params[:id]); return render_error("Payment not found", :not_found) unless payment.payer_id == current_user.id
    return render_error("Payment is already confirmed.", :conflict) if payment.status == "paid"
    return render_error("Mock payments are disabled in production.", :forbidden) if Rails.env.production? && payment.provider != "razorpay"
    if payment.provider == "razorpay"
      return render_error("Payment order mismatch", :unprocessable_entity) unless payment.provider_order_id.present? && ActiveSupport::SecurityUtils.secure_compare(payment.provider_order_id, params[:orderId].to_s)
      expected = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_KEY_SECRET"), "#{payment.provider_order_id}|#{params[:paymentId]}")
      return render_error("Invalid payment signature", :unprocessable_entity) unless ActiveSupport::SecurityUtils.secure_compare(expected, params[:signature].to_s)
      provider_payment = RazorpayGateway.new.payment(params[:paymentId])
      valid_provider_payment = provider_payment["status"] == "captured" &&
        provider_payment["order_id"].to_s == payment.provider_order_id &&
        provider_payment["amount"].to_i == payment.amount * 100 &&
        provider_payment["currency"].to_s.upcase == payment.currency
      return render_error("Payment has not been captured for the expected amount.", :unprocessable_entity) unless valid_provider_payment
    end
    payment.with_lock do
      return render_error("Payment is already confirmed.", :conflict) if payment.status == "paid"
      payment.update!(status: "paid", provider_payment_id: params[:paymentId])
    end
    render json: { ok: true }
  rescue RazorpayGateway::GatewayError => error
    render_error(error.message, :bad_gateway)
  end

  def payments
    booking = BookingRequest.includes(:act).find(params[:id]); return render_error("Booking not found", :not_found) unless [booking.requester_id, booking.act.owner_id].include?(current_user.id)
    render json: { payments: booking.booking_payments.order(created_at: :desc) }
  end

  private
  def owned_booking = BookingRequest.joins(:act).where(acts: { owner_id: current_user.id }).find(params[:id])
  def booking_json(b)
    quote = b.booking_quotes.max_by(&:created_at)
    quote_json = quote && {
      id: quote.id, performanceFee: quote.performance_fee, travelFee: quote.travel_fee,
      productionFee: quote.production_fee, otherFee: quote.other_fee, total: quote.total,
      currency: quote.currency, depositPercent: quote.deposit_percent, validUntil: quote.valid_until,
      inclusions: quote.inclusions, exclusions: quote.exclusions,
      cancellationTerms: quote.cancellation_terms, status: quote.status
    }
    b.attributes.merge(actName: b.act.name, requesterName: b.requester.name, isOwner: b.act.owner_id == current_user.id, isRequester: b.requester_id == current_user.id, latestQuoteTotal: quote&.total, latestQuoteCurrency: quote&.currency, latestDepositPercent: quote&.deposit_percent, latestQuote: quote_json, paidAmount: b.booking_payments.select { _1.status == "paid" }.sum(&:amount), paymentCount: b.booking_payments.size)
  end
end
