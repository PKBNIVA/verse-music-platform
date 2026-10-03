class User < ApplicationRecord
  has_secure_password
  has_one :profile, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :jobs, foreign_key: :employer_id, dependent: :destroy
  has_many :applications, foreign_key: :candidate_id, dependent: :destroy
  has_many :saved_jobs, dependent: :destroy
  has_many :job_alerts, dependent: :destroy
  has_many :portfolio_items, dependent: :destroy
  has_many :portfolios, -> { where(owner_type: "user") }, foreign_key: :owner_id, dependent: :destroy, inverse_of: false
  has_many :resumes, dependent: :destroy
  has_many :career_entries, dependent: :delete_all
  has_many :notifications, dependent: :destroy
  has_many :email_tokens, dependent: :destroy
  has_many :availability_windows, dependent: :destroy
  has_many :recent_activities, dependent: :destroy
  has_many :verification_requests, dependent: :destroy
  has_many :reports, foreign_key: :reporter_id, dependent: :destroy
  has_many :problem_reports, dependent: :destroy
  has_many :reviews, foreign_key: :author_id, dependent: :destroy
  has_many :talent_folders, foreign_key: :owner_id, dependent: :destroy
  has_many :urgent_requests, foreign_key: :requester_id, dependent: :destroy
  has_many :owned_acts, class_name: "Act", foreign_key: :owner_id, dependent: :destroy
  has_many :booking_requests, foreign_key: :requester_id, dependent: :destroy
  has_many :organizations, foreign_key: :owner_id, dependent: :destroy
  has_many :band_projects, foreign_key: :owner_id, dependent: :destroy
  has_many :crew_plans, foreign_key: :owner_id, dependent: :destroy
  has_many :user_blocks, foreign_key: :blocker_id, dependent: :delete_all
  has_many :blocked_by, class_name: "UserBlock", foreign_key: :blocked_id, dependent: :delete_all
  has_many :subscriptions, dependent: :destroy
  has_many :billing_attempts, dependent: :destroy
  has_many :auth_connections, as: :owner, dependent: :destroy
  has_many :push_subscriptions, dependent: :delete_all
  has_many :vouches, foreign_key: :voucher_id, dependent: :destroy
  # The name is part of the profile's search document (Search::Targets::TALENT).
  after_update { Search::Indexer.refresh("talent", id) if saved_change_to_name? }
  # A newly verified phone changes a pending verification request's evidence score.
  after_commit -> { Verification::RescoreJob.for_user(id) }, if: -> { saved_change_to_phone_verified_at? && phone_verified_at.present? }
  belongs_to :vouched_by, class_name: "User", optional: true

  enum :role, { jobseeker: "jobseeker", employer: "employer", admin: "admin" }, validate: true
  enum :status, { active: "active", suspended: "suspended", pending: "pending", deleted: "deleted" }, validate: true

  validates :name, length: { minimum: 2, maximum: 120 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  # Operator-set passwords (db/seeds.rb) skip the strength rule; every password a person chooses through the API is checked.
  attr_accessor :skip_password_strength
  validate :password_strength, if: -> { password.present? && !skip_password_strength }
  validates :synthetic_batch, format: { with: /\A[a-z0-9][a-z0-9-]{2,63}\z/ }, allow_nil: true
  normalizes :email, with: ->(value) { value.strip.downcase }

  scope :synthetic, ->(batch = nil) { batch.present? ? where(synthetic_batch: batch) : where.not(synthetic_batch: nil) }
  scope :organic, -> { where(synthetic_batch: nil) }
  # Professionals whose profiles may be shown to other users (talent pages, folders).
  scope :discoverable_talent, -> { jobseeker.active.where(profile_complete: true) }

  # Someone has just proved they control this account's mailbox (an emailed sign-in code, or
  # Google's verified email) but the address was never verified: whoever registered it first
  # may be a stranger who chose the password. Drop that password, its sessions and any pending
  # links so only the proven mailbox owner can get in (they sign in with a code, Google or a reset).
  # Returns true when a password the person had chosen was dropped (so they should be told).
  def reclaim_unverified_credentials!
    return false if email_verified? || admin?

    had_password = password_set?
    # A random unusable password: the strength rule is for passwords people choose, and a random one
    # can, rarely, contain the name or email ("Code User" vs "...coDe..."), which failed the sign-in.
    self.skip_password_strength = true
    update!(password: SecureRandom.base58(32), password_set_at: nil, phone: nil, phone_verified_at: nil)
    Session.revoke!(sessions)
    auth_connections.destroy_all
    email_tokens.where(used_at: nil).update_all(used_at: Time.current)
    had_password
  end

  def profileComplete = profile_complete
  def emailVerified = email_verified

  # False for an account that has never had a password the person themselves chose (created,
  # or later signed into only, via Google or an emailed code): AccountController#change_password
  # and AuthController's Google/connection paths use this to keep at least one real sign-in
  # method and to give a clearer message than "incorrect password".
  def password_set? = password_set_at.present?

  private

  def password_strength
    violation = PasswordStrength.violation(password, email:, name:)
    errors.add(:password, violation) if violation
  end
end
