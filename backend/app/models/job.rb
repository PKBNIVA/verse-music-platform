class Job < ApplicationRecord
  belongs_to :employer, class_name: "User"
  has_many :applications, dependent: :destroy
  has_many :saved_jobs, dependent: :destroy
  has_many :job_alert_deliveries, dependent: :destroy

  attribute :skills, :json, default: -> { [] }
  attribute :languages, :json, default: -> { [] }
  attribute :screening_questions, :json, default: -> { [] }

  enum :status, { draft: "draft", pending: "pending", published: "published", rejected: "rejected", closed: "closed" }, validate: true
  validates :title, :company, presence: true
  validates :title, length: { maximum: 160 }
  # Drafts (and drafts that were closed) may be incomplete; a job is fully validated whenever it
  # is submitted for review or live.
  validates :location, presence: true, if: :listed?
  validates :description, length: { minimum: 60 }, if: :listed?
  # Upper bounds keep values inside the 32-bit integer columns (larger ones raise instead of validating).
  validates :slots, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }, allow_nil: true
  validates :compensation_min, :compensation_max, numericality: { greater_than_or_equal_to: 0, less_than: 2**31 }, allow_nil: true
  validate :compensation_range_is_ordered
  validate :screening_questions_are_bounded

  # Adds an `applications_total` column computed by a correlated COUNT (served by the
  # applications(job_id, candidate_id) index) so listings never load application rows.
  scope :with_applications_count, -> {
    select(arel_table[Arel.star], "(SELECT COUNT(*) FROM applications WHERE applications.job_id = jobs.id) AS applications_total")
  }

  def applications_count
    has_attribute?(:applications_total) ? self[:applications_total].to_i : applications.count
  end

  def api_json
    attributes.except("applications_total").merge(
      "type" => kind,
      "portfolioRequired" => portfolio_required,
      "screeningQuestions" => screening_questions,
      "employerName" => employer.name,
      "employerVerified" => employer.profile&.verified || false,
      "demo" => SyntheticQa::Demo.user?(employer),
      "applicationsCount" => applications_count,
      "createdAt" => created_at,
      "updatedAt" => updated_at
    )
  end

  def listed? = pending? || published?

  private

  def compensation_range_is_ordered
    return if compensation_min.blank? || compensation_max.blank? || compensation_min <= compensation_max
    errors.add(:compensation_max, "must be at least the minimum")
  end

  def screening_questions_are_bounded
    questions = Array(screening_questions)
    errors.add(:screening_questions, "are limited to 8") if questions.length > 8
    errors.add(:screening_questions, "must each be under 300 characters") if questions.any? { _1.to_s.length > 300 }
  end
end
