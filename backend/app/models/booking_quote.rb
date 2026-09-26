class BookingQuote < ApplicationRecord
  belongs_to :booking_request
  belongs_to :created_by, class_name: "User"
  has_many :booking_payments
  MAX_FEE = 100_000_000

  validates :performance_fee, :travel_fee, :production_fee, :other_fee, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_FEE }
  validates :performance_fee, numericality: { greater_than: 0 }, allow_nil: true
  validates :deposit_percent, numericality: { only_integer: true, in: 1..100 }
  validates :currency, :status, presence: true
  # Deposits are charged in this currency, so it must be a valid ISO code up front.
  validates :currency, format: { with: /\A[A-Z]{3}\z/, message: "must be a 3-letter code such as INR" }
  validate :valid_until_is_future, on: :create

  def total = performance_fee + travel_fee + production_fee + other_fee

  private

  def valid_until_is_future
    errors.add(:valid_until, "must be in the future") if valid_until.present? && valid_until <= Time.current
  end
end
