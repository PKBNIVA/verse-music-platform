class BookingPayment < ApplicationRecord
  KINDS = %w[deposit balance refund].freeze
  PROVIDERS = %w[internal razorpay].freeze
  STATUSES = %w[created paid failed refunded].freeze

  belongs_to :booking_request
  belongs_to :booking_quote, optional: true
  belongs_to :payer, class_name: "User"
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, :currency, :provider, :status, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }

  UNISSUED_ORDER_TTL = 30.minutes

  # Razorpay order receipts are limited to 40 characters ("book_<uuid>" plus a prefix is not).
  def self.receipt_for(id) = "dep_#{id.to_s.split("_", 2).last.delete("-")}".first(40)

  def provider_receipt = self.class.receipt_for(id)

  # A capture is final money movement. It is applied to a `created` payment, and
  # also to a payment that Razorpay previously reported as failed for the same
  # order (a customer can retry inside the same checkout after a decline), so a
  # real capture is never silently discarded.
  def apply_capture!(entity:, event_at:, event_id:)
    transaction do
      booking_request.lock!
      lock!
      recovering = provider_failed?
      return :stale if !recovering && provider_state_at.present? && event_at < provider_state_at
      return :already_paid if status == "paid"
      return :invalid_transition unless status == "created" || recovering
      return :invalid_order unless provider_order_id.present? && secure_match?(provider_order_id, entity["order_id"])
      return :invalid_state unless entity["status"] == "captured"
      return :invalid_amount unless entity["amount"].to_i == amount * 100
      return :invalid_currency unless entity["currency"].to_s.upcase == currency

      if recovering
        other = BookingPayment.lock.where(booking_request_id:, kind:, status: %w[created paid]).where.not(id:).first
        # Two captured deposits for one booking: keep the ledger truthful and leave the refund to operations.
        return :duplicate_capture if other&.status == "paid"

        other&.update!(status: "failed", provider_state_at: event_at, last_provider_event_id: event_id)
      end
      update!(status: "paid", provider_payment_id: entity["id"], provider_state_at: [event_at, provider_state_at].compact.max, last_provider_event_id: event_id)
      recovering ? :applied_after_failure : :applied
    end
  end

  # Razorpay `payment.failed` for this order. The payment becomes `failed` so the
  # partial unique index frees up and the payer can start a fresh deposit.
  def apply_failure!(entity:, event_at:, event_id:)
    with_lock do
      return :stale if provider_state_at.present? && event_at < provider_state_at
      return :already_paid if status == "paid"
      return :already_failed if status == "failed"
      return :invalid_transition unless status == "created"
      return :invalid_order unless provider_order_id.present? && secure_match?(provider_order_id, entity["order_id"])

      update!(status: "failed", provider_state_at: event_at, last_provider_event_id: event_id)
      :applied
    end
  end

  # Razorpay `refund.processed`. Only a full refund of a paid payment changes the
  # ledger status; partial refunds are recorded on the billing event only.
  def apply_refund!(refund:, payment_entity:, event_at:, event_id:)
    with_lock do
      return :already_refunded if status == "refunded"
      return :invalid_transition unless status == "paid"
      return :invalid_payment unless provider_payment_id.present? && secure_match?(provider_payment_id, refund["payment_id"])
      return :invalid_state unless refund["status"] == "processed"

      refunded_paise = refund["amount"].to_i
      if payment_entity.is_a?(Hash) && secure_match?(provider_payment_id, payment_entity["id"])
        refunded_paise = [refunded_paise, payment_entity["amount_refunded"].to_i].max
      end
      return :partial_refund if refunded_paise < amount * 100

      update!(status: "refunded", provider_state_at: [event_at, provider_state_at].compact.max, last_provider_event_id: event_id)
      :applied
    end
  end

  # A Razorpay payment row that never received a provider order (the create call
  # crashed or was ambiguous) blocks a retry through the partial unique index.
  # After the TTL nothing can pay it (the browser never saw an order id), so it
  # is safe to fail it and its attempt. Returns true when this call expired it.
  def expire_unissued!(now: Time.current)
    with_lock do
      return false unless unissued_expired?(now:)

      update!(status: "failed")
      BillingAttempt.where(resource_type: "BookingPayment", resource_id: id, state: %w[pending ambiguous], provider_resource_id: nil)
        .find_each { _1.mark_stale!(now:) }
      true
    end
  end

  def unissued_expired?(now: Time.current)
    provider == "razorpay" && status == "created" && provider_order_id.blank? && created_at <= now - UNISSUED_ORDER_TTL
  end

  # Failed by a Razorpay payment event (not by a local order-creation error).
  def provider_failed?
    status == "failed" && provider_order_id.present? && last_provider_event_id.present?
  end

  private

  def secure_match?(expected, actual)
    actual.present? && ActiveSupport::SecurityUtils.secure_compare(expected.to_s, actual.to_s)
  end
end
