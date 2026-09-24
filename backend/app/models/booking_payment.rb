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

  def apply_capture!(entity:, event_at:, event_id:)
    with_lock do
      return :stale if provider_state_at.present? && event_at < provider_state_at
      return :already_paid if status == "paid"
      return :invalid_transition unless status == "created"
      return :invalid_order unless provider_order_id.present? && secure_match?(provider_order_id, entity["order_id"])
      return :invalid_state unless entity["status"] == "captured"
      return :invalid_amount unless entity["amount"].to_i == amount * 100
      return :invalid_currency unless entity["currency"].to_s.upcase == currency

      update!(status: "paid", provider_payment_id: entity["id"], provider_state_at: event_at, last_provider_event_id: event_id)
      :applied
    end
  end

  private

  def secure_match?(expected, actual)
    actual.present? && ActiveSupport::SecurityUtils.secure_compare(expected.to_s, actual.to_s)
  end
end
