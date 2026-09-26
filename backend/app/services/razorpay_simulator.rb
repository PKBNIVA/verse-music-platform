# Local stand-in for api.razorpay.com so complete billing flows run without credentials.
#
# - Enabled only with RAZORPAY_SIMULATOR=true outside production and only with a test-mode
#   key (`rzp_test_`). In production it is refused unconditionally (see RazorpayConfig.simulator?).
# - RazorpayGateway plugs RazorpaySimulator::Adapter into Faraday, so the real gateway code
#   (Basic auth, JSON encoding, error/ambiguity mapping) runs against it.
# - Entities follow Razorpay's documented JSON shapes (subscription, order, payment, refund,
#   collection, error envelope) closely enough for the server's validation to be meaningful.
# - Checkout and lifecycle helpers produce what the real Checkout/webhooks would: handler
#   responses with a valid HMAC signature, and signed webhook deliveries.
#
# State lives in one process-wide store (memory). In development it survives code reloads.
class RazorpaySimulator
  class Refused < StandardError; end
  class Error < StandardError
    attr_reader :status, :body

    def initialize(status, description, code: "BAD_REQUEST_ERROR", field: nil, reason: "input_validation_failed")
      @status = status
      @body = { "error" => { "code" => code, "description" => description, "source" => "business", "step" => "payment_initiation",
                             "reason" => reason, "metadata" => {}, "field" => field }.compact }
      super(description)
    end
  end

  MONTH = 30 * 24 * 3600
  TRIAL_AUTH_PAISE = 500
  SUBSCRIPTION_ACTIONS = %w[activate charge pending halt pause resume cancel complete].freeze

  class << self
    def enabled? = RazorpayConfig.simulator?

    def assert_enabled!
      raise Refused, "The Razorpay simulator is never available in production" if Rails.env.production?
      raise Refused, "The Razorpay simulator is disabled (set RAZORPAY_SIMULATOR=true with an rzp_test_ key)" unless enabled?
    end

    def instance
      holder = Rails.application.config.x
      holder.razorpay_simulator ||= new
    end

    def reset! = Rails.application.config.x.razorpay_simulator = new
  end

  def initialize
    @mutex = Mutex.new
    @subscriptions = {}
    @orders = {}
    @payments = {}
    @refunds = {}
    @faults = []
    @sequence = 0
  end

  # ---- Fault injection (tests / rehearsal) -------------------------------------------------
  # mode: :timeout_before (nothing created), :timeout_after (created, response lost),
  #       :server_error (HTTP 500 after creation), :bad_request (HTTP 400, nothing created)
  def inject_fault(operation, mode)
    synchronize { @faults << [operation.to_sym, mode.to_sym] }
  end

  # ---- HTTP API ----------------------------------------------------------------------------
  def handle(method, url, authorization, raw_body)
    self.class.assert_enabled!
    uri = URI(url.to_s)
    authenticate!(authorization)
    body = raw_body.present? ? JSON.parse(raw_body) : {}
    query = Rack::Utils.parse_query(uri.query.to_s)
    path = uri.path.delete_prefix("/v1/")
    [200, route(method.to_s.downcase, path, body, query)]
  rescue Error => error
    [error.status, error.body]
  rescue JSON::ParserError
    [400, Error.new(400, "The request body is not valid JSON").body]
  end

  def subscription(id) = synchronize { deep(@subscriptions[id]) }
  def order(id) = synchronize { deep(@orders[id]) }
  def payment(id) = synchronize { deep(@payments[id]) }
  def payments_for_order(order_id) = synchronize { @payments.values.select { _1["order_id"] == order_id }.map { deep(_1) } }

  # ---- Checkout (what checkout.js would do in the browser) --------------------------------
  # Returns { response: handler_payload } on success, { error: checkout_error } on failure,
  # { dismissed: true } on dismiss, plus :events (webhooks Razorpay would send).
  def checkout_subscription(subscription_id, outcome:)
    synchronize do
      sub = @subscriptions[subscription_id] or raise Error.new(400, "The id provided does not exist", field: "subscription_id")
      raise Error.new(400, "Subscription is not in a state that allows authentication", reason: "invalid_state") unless sub["status"] == "created"
      next { dismissed: true, events: [] } if outcome.to_s == "dismiss"

      trial = sub["start_at"].to_i > now
      amount = trial ? TRIAL_AUTH_PAISE : plan_amount!(sub["plan_id"])
      payment = new_payment(amount:, currency: "INR", order_id: nil, notes: sub["notes"], description: "Subscription #{sub["id"]}", invoice_id: nil)
      payment["subscription_id"] = sub["id"]
      if outcome.to_s == "fail"
        fail_payment!(payment)
        next { error: checkout_error(payment), events: [event("payment.failed", payment:)] }
      end

      capture_payment!(payment)
      sub["auth_attempts"] += 1
      sub["payment_method"] = "card"
      events = []
      if trial
        payment["amount_refunded"] = amount
        payment["refund_status"] = "full"
        payment["status"] = "refunded"
        sub["status"] = "authenticated"
        events << event("subscription.authenticated", subscription: sub)
      else
        sub["status"] = "authenticated"
        events << event("subscription.authenticated", subscription: sub)
        start_cycle!(sub, payment)
        events << event("subscription.activated", subscription: sub, payment:)
        events << event("subscription.charged", subscription: sub, payment:)
      end
      signature = sign("#{payment["id"]}|#{sub["id"]}")
      { response: { "razorpay_payment_id" => payment["id"], "razorpay_subscription_id" => sub["id"], "razorpay_signature" => signature }, events: }
    end
  end

  def checkout_order(order_id, outcome:)
    synchronize do
      order = @orders[order_id] or raise Error.new(400, "The id provided does not exist", field: "order_id")
      raise Error.new(400, "Order has already been paid", reason: "invalid_state") if order["status"] == "paid"
      next { dismissed: true, events: [] } if outcome.to_s == "dismiss"

      order["attempts"] += 1
      order["status"] = "attempted"
      payment = new_payment(amount: order["amount"], currency: order["currency"], order_id: order["id"], notes: order["notes"], description: order["receipt"], invoice_id: nil)
      if outcome.to_s == "fail"
        fail_payment!(payment)
        next { error: checkout_error(payment), events: [event("payment.failed", payment:)] }
      end

      # Auto-capture on (DEPLOYMENT.md go-live checklist): authorized then captured immediately.
      events = [event("payment.authorized", payment: deep(payment.merge("status" => "authorized", "captured" => false)))]
      capture_payment!(payment)
      order["status"] = "paid"
      order["amount_paid"] = order["amount"]
      order["amount_due"] = 0
      events << event("payment.captured", payment:)
      events << event("order.paid", payment:, order:)
      signature = sign("#{order["id"]}|#{payment["id"]}")
      { response: { "razorpay_payment_id" => payment["id"], "razorpay_order_id" => order["id"], "razorpay_signature" => signature }, events: }
    end
  end

  # ---- Subscription lifecycle (what Razorpay does over time) ------------------------------
  def advance_subscription(subscription_id, action)
    raise Error.new(400, "Unknown simulator action #{action}") unless SUBSCRIPTION_ACTIONS.include?(action.to_s)

    synchronize do
      sub = @subscriptions[subscription_id] or raise Error.new(400, "The id provided does not exist", field: "subscription_id")
      case action.to_s
      when "activate"
        require_status!(sub, %w[authenticated])
        payment = charge_payment(sub)
        start_cycle!(sub, payment)
        [event("subscription.activated", subscription: sub, payment:), event("subscription.charged", subscription: sub, payment:)]
      when "charge"
        require_status!(sub, %w[active pending halted])
        payment = charge_payment(sub)
        recovering = sub["status"] != "active"
        start_cycle!(sub, payment)
        events = [event("subscription.charged", subscription: sub, payment:)]
        events.unshift(event("subscription.activated", subscription: sub, payment:)) if recovering
        if sub["remaining_count"].to_i <= 0
          sub["status"] = "completed"
          sub["ended_at"] = now
          events << event("subscription.completed", subscription: sub)
        end
        events
      when "pending"
        require_status!(sub, %w[active])
        payment = charge_payment(sub, fail: true)
        sub["status"] = "pending"
        [event("subscription.pending", subscription: sub, payment:)]
      when "halt"
        require_status!(sub, %w[active pending])
        sub["status"] = "halted"
        [event("subscription.halted", subscription: sub)]
      when "pause"
        require_status!(sub, %w[active])
        sub["status"] = "paused"
        sub["paused_at"] = now
        [event("subscription.paused", subscription: sub)]
      when "resume"
        require_status!(sub, %w[paused halted])
        sub["status"] = "active"
        sub["paused_at"] = nil
        [event("subscription.resumed", subscription: sub)]
      when "cancel"
        require_status!(sub, %w[created authenticated active pending halted paused])
        sub["status"] = "cancelled"
        sub["ended_at"] = now
        [event("subscription.cancelled", subscription: sub)]
      when "complete"
        require_status!(sub, %w[active])
        sub["status"] = "completed"
        sub["ended_at"] = now
        sub["remaining_count"] = 0
        [event("subscription.completed", subscription: sub)]
      end
    end
  end

  # Razorpay dashboard/API refund of a captured payment (full unless amount given).
  def refund_payment(payment_id, amount: nil)
    synchronize do
      payment = @payments[payment_id] or raise Error.new(400, "The id provided does not exist", field: "payment_id")
      raise Error.new(400, "The payment has not been captured", reason: "invalid_state") unless payment["captured"]

      refundable = payment["amount"] - payment["amount_refunded"]
      amount = (amount || refundable).to_i
      raise Error.new(400, "The refund amount provided is greater than amount captured", field: "amount") if amount <= 0 || amount > refundable

      refund = { "id" => next_id("rfnd"), "entity" => "refund", "amount" => amount, "currency" => payment["currency"], "payment_id" => payment["id"],
                 "notes" => {}, "receipt" => nil, "acquirer_data" => { "arn" => nil }, "created_at" => now, "batch_id" => nil,
                 "status" => "processed", "speed_processed" => "normal", "speed_requested" => "normal" }
      @refunds[refund["id"]] = refund
      payment["amount_refunded"] += amount
      payment["refund_status"] = payment["amount_refunded"] >= payment["amount"] ? "full" : "partial"
      payment["status"] = "refunded" if payment["refund_status"] == "full"
      [event("refund.created", refund: refund.merge("status" => "pending"), payment:), event("refund.processed", refund:, payment:)]
    end
  end

  private

  def route(method, path, body, query)
    case [method, path]
    in ["post", "subscriptions"] then create_subscription(body)
    in ["get", "subscriptions"] then collection(synchronize { @subscriptions.values }, query)
    in ["get", %r{\Asubscriptions/[^/]+\z}] then fetch!(@subscriptions, path.split("/").last)
    in ["post", %r{\Asubscriptions/[^/]+/cancel\z}] then cancel_subscription(path.split("/")[1], body)
    in ["post", "orders"] then create_order(body)
    in ["get", "orders"]
      items = synchronize { @orders.values }
      items = items.select { _1["receipt"] == query["receipt"] } if query["receipt"].present?
      collection(items, query)
    in ["get", %r{\Aorders/[^/]+\z}] then fetch!(@orders, path.split("/").last)
    in ["get", %r{\Apayments/[^/]+\z}] then fetch!(@payments, path.split("/").last)
    else raise Error.new(404, "The requested URL was not found on the server.", reason: "NA")
    end
  end

  def create_subscription(body)
    with_fault(:create_subscription) do
      plan_id = body["plan_id"].to_s
      raise Error.new(400, "The plan id field is required.", field: "plan_id") if plan_id.blank?

      plan_amount!(plan_id)
      total = Integer(body["total_count"], exception: false)
      raise Error.new(400, "The total count must be at least 1.", field: "total_count") unless total&.positive?

      start_at = body["start_at"].presence&.to_i
      raise Error.new(400, "Start time cannot be lesser than current time", field: "start_at") if start_at && start_at < now

      synchronize do
        id = next_id("sub")
        @subscriptions[id] = {
          "id" => id, "entity" => "subscription", "plan_id" => plan_id, "customer_id" => nil, "status" => "created",
          "current_start" => nil, "current_end" => nil, "ended_at" => nil, "quantity" => (body["quantity"] || 1).to_i,
          "notes" => stringify(body["notes"]), "charge_at" => start_at || now, "start_at" => start_at, "end_at" => nil,
          "auth_attempts" => 0, "total_count" => total, "paid_count" => 0, "customer_notify" => body["customer_notify"].to_i == 1,
          "created_at" => now, "expire_by" => nil, "short_url" => "https://rzp.io/i/#{SecureRandom.alphanumeric(8)}",
          "has_scheduled_changes" => false, "change_scheduled_at" => nil, "source" => "api", "payment_method" => nil,
          "offer_id" => nil, "remaining_count" => total
        }
        deep(@subscriptions[id])
      end
    end
  end

  def cancel_subscription(id, body)
    synchronize do
      sub = @subscriptions[id] or raise Error.new(400, "The id provided does not exist", field: "id")
      raise Error.new(400, "Subscription is not cancellable in #{sub["status"]} status.", reason: "invalid_state") if %w[cancelled completed expired].include?(sub["status"])

      if body["cancel_at_cycle_end"].to_i == 1
        raise Error.new(400, "Subscription cannot be cancelled at cycle end when it is not active", reason: "invalid_state") unless sub["status"] == "active"

        sub["has_scheduled_changes"] = true
        sub["change_scheduled_at"] = sub["current_end"]
        sub["end_at"] = sub["current_end"]
      else
        sub["status"] = "cancelled"
        sub["ended_at"] = now
      end
      deep(sub)
    end
  end

  def create_order(body)
    with_fault(:create_order) do
      amount = Integer(body["amount"], exception: false)
      raise Error.new(400, "The amount must be atleast INR 1.00", field: "amount") unless amount && amount >= 100
      currency = body["currency"].to_s
      raise Error.new(400, "The currency field is invalid.", field: "currency") unless currency.match?(/\A[A-Z]{3}\z/)
      raise Error.new(400, "The receipt may not be greater than 40 characters.", field: "receipt") if body["receipt"].to_s.length > 40

      synchronize do
        id = next_id("order")
        @orders[id] = { "id" => id, "entity" => "order", "amount" => amount, "amount_paid" => 0, "amount_due" => amount, "currency" => currency,
                        "receipt" => body["receipt"], "offer_id" => nil, "status" => "created", "attempts" => 0,
                        "notes" => stringify(body["notes"]), "created_at" => now }
        deep(@orders[id])
      end
    end
  end

  def with_fault(operation)
    fault = synchronize { (index = @faults.index { _1.first == operation }) && @faults.delete_at(index) }
    mode = fault&.last
    raise Faraday::TimeoutError, "simulated timeout" if mode == :timeout_before
    raise Error.new(400, "Simulated validation failure") if mode == :bad_request

    result = yield
    raise Faraday::TimeoutError, "simulated timeout after create" if mode == :timeout_after
    raise Error.new(500, "We are facing some trouble completing your request at the moment. Please try again shortly.", code: "SERVER_ERROR", reason: "server_error") if mode == :server_error

    result
  end

  def fetch!(store, id) = synchronize { deep(store[id]) || raise(Error.new(400, "The id provided does not exist", field: "id")) }

  def collection(items, query)
    synchronize do
      from = query["from"].presence&.to_i
      to = query["to"].presence&.to_i
      items = items.select { (!from || _1["created_at"] >= from) && (!to || _1["created_at"] <= to) }.sort_by { -_1["created_at"] }
      items = items.drop(query["skip"].to_i).first((query["count"].presence || 10).to_i.clamp(1, 100))
      { "entity" => "collection", "count" => items.size, "items" => items.map { deep(_1) } }
    end
  end

  def authenticate!(authorization)
    expected = "Basic #{Base64.strict_encode64("#{ENV["RAZORPAY_KEY_ID"]}:#{ENV["RAZORPAY_KEY_SECRET"]}")}"
    return if ENV["RAZORPAY_KEY_SECRET"].present? && ActiveSupport::SecurityUtils.secure_compare(expected, authorization.to_s)

    raise Error.new(401, "Authentication failed", reason: "NA")
  end

  def plan_amount!(plan_id)
    code = Billing::BillingController::PLANS.keys.find { ENV["RAZORPAY_PLAN_#{_1.upcase}"].presence == plan_id }
    monthly = code && Billing::BillingController::PLANS.dig(code, :monthly)
    raise Error.new(400, "The id provided does not exist", field: "plan_id") unless monthly.to_i.positive?

    monthly * 100
  end

  def new_payment(amount:, currency:, order_id:, notes:, description:, invoice_id:)
    id = next_id("pay")
    @payments[id] = {
      "id" => id, "entity" => "payment", "amount" => amount, "currency" => currency, "status" => "created", "order_id" => order_id,
      "invoice_id" => invoice_id, "international" => false, "method" => "card", "amount_refunded" => 0, "refund_status" => nil,
      "captured" => false, "description" => description, "card_id" => "card_#{SecureRandom.alphanumeric(14)}", "bank" => nil, "wallet" => nil,
      "vpa" => nil, "email" => "void@razorpay.com", "contact" => "+919999999999", "notes" => deep(notes || {}), "fee" => nil, "tax" => nil,
      "error_code" => nil, "error_description" => nil, "error_source" => nil, "error_step" => nil, "error_reason" => nil,
      "acquirer_data" => { "auth_code" => nil }, "created_at" => now
    }
  end

  def capture_payment!(payment)
    fee = (payment["amount"] * 0.02).round
    payment.merge!("status" => "captured", "captured" => true, "fee" => fee, "tax" => (fee * 0.18).round, "acquirer_data" => { "auth_code" => SecureRandom.random_number(10**6).to_s.rjust(6, "0") })
  end

  def fail_payment!(payment)
    payment.merge!("status" => "failed", "error_code" => "BAD_REQUEST_ERROR", "error_description" => "Your payment has been declined by the bank.",
                   "error_source" => "bank", "error_step" => "payment_authorization", "error_reason" => "payment_declined")
  end

  def checkout_error(payment)
    { "code" => payment["error_code"], "description" => payment["error_description"], "source" => payment["error_source"], "step" => payment["error_step"],
      "reason" => payment["error_reason"], "metadata" => { "payment_id" => payment["id"], "order_id" => payment["order_id"] }.compact }
  end

  def charge_payment(sub, fail: false)
    payment = new_payment(amount: plan_amount!(sub["plan_id"]), currency: "INR", order_id: nil, notes: sub["notes"], description: "Subscription #{sub["id"]}", invoice_id: next_id("inv"))
    payment["subscription_id"] = sub["id"]
    fail ? fail_payment!(payment) : capture_payment!(payment)
    payment
  end

  def start_cycle!(sub, _payment)
    start = [sub["current_end"].to_i, now].max
    sub.merge!("status" => "active", "current_start" => start, "current_end" => start + MONTH, "charge_at" => start + MONTH,
               "paid_count" => sub["paid_count"] + 1, "remaining_count" => [sub["total_count"] - sub["paid_count"] - 1, 0].max)
  end

  def require_status!(sub, allowed)
    return if allowed.include?(sub["status"])

    raise Error.new(400, "Subscription is in #{sub["status"]} status; expected #{allowed.join("/")}.", reason: "invalid_state")
  end

  def event(name, **entities)
    { "entity" => "event", "account_id" => "acc_Simulator000001", "event" => name, "contains" => entities.keys.map(&:to_s),
      "payload" => entities.to_h { |key, value| [key.to_s, { "entity" => deep(value) }] }, "created_at" => now }
  end

  def sign(data) = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("RAZORPAY_KEY_SECRET"), data)

  def next_id(prefix)
    @sequence += 1
    "#{prefix}_Sim#{@sequence.to_s.rjust(4, "0")}#{SecureRandom.alphanumeric(7)}"
  end

  def now = Time.current.to_i
  def stringify(value) = value.is_a?(Hash) ? value.to_h { |k, v| [k.to_s, v.is_a?(Hash) ? stringify(v) : v.to_s] } : {}
  def deep(value) = value && JSON.parse(JSON.generate(value))

  def synchronize(&)
    @mutex.owned? ? yield : @mutex.synchronize(&)
  end

  # Faraday adapter that answers api.razorpay.com requests from the simulator.
  class Adapter < Faraday::Adapter
    def call(env)
      super
      status, body = RazorpaySimulator.instance.handle(env.method, env.url, env.request_headers["Authorization"], env.request_body)
      save_response(env, status, JSON.generate(body), { "Content-Type" => "application/json" })
      @app.call(env)
    end
  end

  # Correctly signed webhook deliveries, including deliberate duplicates and reordering.
  module Webhooks
    module_function

    def signed(payload, event_id: nil, secret: ENV.fetch("RAZORPAY_WEBHOOK_SECRET"))
      body = payload.is_a?(String) ? payload : JSON.generate(payload)
      { body:, headers: { "Content-Type" => "application/json", "X-Razorpay-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body),
                          "X-Razorpay-Event-Id" => event_id || "evt_Sim#{SecureRandom.alphanumeric(14)}" } }
    end

    # Deliver over HTTP to a running server (development). Returns [{event, status, body}].
    def deliver(deliveries, url)
      deliveries.map do |delivery|
        response = Faraday.post(url, delivery[:body], delivery[:headers]) { _1.options.timeout = 10 }
        { event: JSON.parse(delivery[:body])["event"], eventId: delivery[:headers]["X-Razorpay-Event-Id"], status: response.status, body: (JSON.parse(response.body) rescue response.body) }
      end
    end
  end
end
