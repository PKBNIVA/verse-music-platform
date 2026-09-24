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

  def api_json
    attributes.merge(
      "type" => kind,
      "portfolioRequired" => portfolio_required,
      "screeningQuestions" => screening_questions,
      "employerName" => employer.name,
      "employerVerified" => employer.profile&.verified || false,
      "applicationsCount" => applications.size,
      "createdAt" => created_at,
      "updatedAt" => updated_at
    )
  end
end
