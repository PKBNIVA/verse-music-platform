class Job < ApplicationRecord
  belongs_to :employer, class_name: "User"
  has_many :applications, dependent: :destroy
  has_many :saved_jobs, dependent: :destroy
  has_many :job_alert_deliveries, dependent: :destroy

  attribute :skills, :json, default: -> { [] }
  attribute :languages, :json, default: -> { [] }
  attribute :screening_questions, :json, default: -> { [] }

  enum :status, { draft: "draft", pending: "pending", published: "published", rejected: "rejected", closed: "closed" }, validate: true
  validates :title, :company, :location, presence: true
  validates :description, length: { minimum: 60 }

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
      "applicationsCount" => applications_count,
      "createdAt" => created_at,
      "updatedAt" => updated_at
    )
  end
end
