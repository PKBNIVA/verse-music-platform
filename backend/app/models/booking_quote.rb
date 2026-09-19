class BookingQuote < ApplicationRecord
  belongs_to :booking_request
  belongs_to :created_by, class_name: "User"
  has_many :booking_payments
  validates :performance_fee, :travel_fee, :production_fee, :other_fee, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :deposit_percent, numericality: { only_integer: true, in: 1..100 }
  validates :currency, :status, presence: true
  validate :valid_until_is_future, on: :create

  def total = performance_fee + travel_fee + production_fee + other_fee

  private

  def valid_until_is_future
    errors.add(:valid_until, "must be in the future") if valid_until.present? && valid_until <= Time.current
  end
end
