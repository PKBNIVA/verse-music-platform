class BookingPayment < ApplicationRecord
  belongs_to :booking_request
  belongs_to :booking_quote, optional: true
  belongs_to :payer, class_name: "User"
end
