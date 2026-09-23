class AvailabilityWindow < ApplicationRecord
  belongs_to :user
  validates :start_at, :end_at, presence: true
  validates :status, inclusion: { in: %w[available hold tentative booked unavailable] }
  validate :ends_after_start

  private

  def ends_after_start
    errors.add(:end_at, "must be after the start") if start_at && end_at && end_at <= start_at
  end
end
