class UrgentRequest < ApplicationRecord
  belongs_to :requester, class_name: "User"
  has_many :urgent_request_responses, dependent: :destroy
  validates :title, :role_name, :city, :start_at, presence: true
  validates :status, inclusion: { in: %w[open filled cancelled] }
  validates :budget_min, :budget_max, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :valid_schedule_and_budget

  private

  def valid_schedule_and_budget
    errors.add(:end_at, "must be after the start") if start_at && end_at && end_at <= start_at
    errors.add(:budget_max, "must be at least the minimum") if budget_min && budget_max && budget_max < budget_min
  end
end
