class BookingQuote < ApplicationRecord
  belongs_to :booking_request
  belongs_to :created_by, class_name: "User"
  has_many :booking_payments
  def total = performance_fee + travel_fee + production_fee + other_fee
end
