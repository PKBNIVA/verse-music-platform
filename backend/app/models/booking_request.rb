class BookingRequest < ApplicationRecord
  belongs_to :act
  belongs_to :requester, class_name: "User"
  has_many :booking_quotes, dependent: :destroy
  has_many :booking_payments, dependent: :destroy
end
