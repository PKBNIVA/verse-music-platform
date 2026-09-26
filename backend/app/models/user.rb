class User < ApplicationRecord
  has_secure_password
  has_one :profile, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :jobs, foreign_key: :employer_id, dependent: :destroy
  has_many :applications, foreign_key: :candidate_id, dependent: :destroy
  has_many :saved_jobs, dependent: :destroy
  has_many :job_alerts, dependent: :destroy
  has_many :portfolio_items, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :email_tokens, dependent: :destroy
  has_many :availability_windows, dependent: :destroy
  has_many :recent_activities, dependent: :destroy
  has_many :verification_requests, dependent: :destroy
  has_many :reports, foreign_key: :reporter_id, dependent: :destroy
  has_many :reviews, foreign_key: :author_id, dependent: :destroy
  has_many :talent_folders, foreign_key: :owner_id, dependent: :destroy
  has_many :urgent_requests, foreign_key: :requester_id, dependent: :destroy
  has_many :owned_acts, class_name: "Act", foreign_key: :owner_id, dependent: :destroy
  has_many :booking_requests, foreign_key: :requester_id, dependent: :destroy
  has_many :organizations, foreign_key: :owner_id, dependent: :destroy
  has_many :band_projects, foreign_key: :owner_id, dependent: :destroy
  has_many :crew_plans, foreign_key: :owner_id, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :billing_attempts, dependent: :destroy

  enum :role, { jobseeker: "jobseeker", employer: "employer", admin: "admin" }, validate: true
  enum :status, { active: "active", suspended: "suspended", pending: "pending" }, validate: true

  validates :name, length: { minimum: 2, maximum: 120 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 10 }, if: -> { password.present? }
  validates :synthetic_batch, format: { with: /\A[a-z0-9][a-z0-9-]{2,63}\z/ }, allow_nil: true
  normalizes :email, with: ->(value) { value.strip.downcase }

  scope :synthetic, ->(batch = nil) { batch.present? ? where(synthetic_batch: batch) : where.not(synthetic_batch: nil) }
  scope :organic, -> { where(synthetic_batch: nil) }
  # Professionals whose profiles may be shown to other users (talent pages, folders).
  scope :discoverable_talent, -> { jobseeker.active.where(profile_complete: true) }

  def profileComplete = profile_complete
  def emailVerified = email_verified
end
