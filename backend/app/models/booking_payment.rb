class BookingPayment < ApplicationRecord
  belongs_to :booking_request
  belongs_to :booking_quote, optional: true
  belongs_to :payer, class_name: "User"
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, :currency, :provider, :status, presence: true
end
