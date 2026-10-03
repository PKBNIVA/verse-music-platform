class UrgentRequest < ApplicationRecord
  # "cancelled" is kept as an accepted legacy value (old rows, the admin's original action);
  # "closed" is what the hirer's own "Close" button on the request page writes going forward.
  STATUSES = %w[open filled cancelled closed expired].freeze
  OPEN_STATUSES = %w[open].freeze
  # Requests older than this are past their usefulness and are hidden from the open list
  # even when nobody marked them cancelled/closed/expired (see UrgentRequestsController#index
  # and Admin::UrgentRequestsController#sweep_expired).
  STALE_AFTER = 3.days

  belongs_to :requester, class_name: "User"
  belongs_to :filled_by, class_name: "User", optional: true
  has_many :urgent_request_responses, dependent: :destroy
  has_many :urgent_request_notifications, dependent: :destroy
  validates :title, :role_name, :city, :start_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :budget_min, :budget_max, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :valid_schedule_and_budget
  before_validation :set_expires_at, on: :create
  after_commit -> { Verification::RescoreJob.for_user(filled_by_id) if status == "filled" }
  # Live status for the hirer's request page (Realtime). UrgentMatchJob writes match_status with
  # update_columns and broadcasts itself.
  after_update_commit -> { Realtime.urgent_request_changed(self) if (saved_changes.keys & %w[status match_status filled_by_id]).any? }

  scope :open_and_recent, -> { where(status: "open").where("start_at >= ?", STALE_AFTER.ago) }
  # Open requests past their expiry warning point (6 hours before expires_at), that have at
  # least one response and have not already been warned. Used by UrgentRequestsSweepJob.
  scope :due_for_expiry_warning, -> {
    where(status: "open", expiry_warned_at: nil)
      .where("expires_at IS NOT NULL AND expires_at <= ?", 6.hours.from_now)
      .where(id: UrgentRequestResponse.select(:urgent_request_id))
  }
  scope :due_to_expire, -> { where(status: "open").where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }

  # Minutes since the request was posted, for the admin "no response after 60 min" flag.
  def age_minutes = ((Time.current - created_at) / 60).round

  # Whether this request was filled within 24 hours of being posted (the launch metric).
  def filled_within_24h? = status == "filled" && updated_at <= created_at + 24.hours

  def open? = status == "open"

  private

  def set_expires_at
    self.expires_at ||= (created_at || Time.current) + UrgentConfig.expire_after
  end

  def valid_schedule_and_budget
    errors.add(:end_at, "must be after the start") if start_at && end_at && end_at <= start_at
    errors.add(:budget_max, "must be at least the minimum") if budget_min && budget_max && budget_max < budget_min
  end
end
