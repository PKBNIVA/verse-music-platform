class BookingPayment < ApplicationRecord
  belongs_to :booking_request
  belongs_to :booking_quote, optional: true
  belongs_to :payer, class_name: "User"
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, :currency, :provider, :status, presence: true
  validates :kind, inclusion: { in: %w[deposit balance refund] }
  validates :provider, inclusion: { in: %w[internal razorpay] }
  validates :status, inclusion: { in: %w[created paid failed refunded] }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
end
