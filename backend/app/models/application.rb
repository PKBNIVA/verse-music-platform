class Application < ApplicationRecord
  STATUS_TRANSITIONS = {
    "Applied" => ["Under Review", "Shortlisted", "Interview Scheduled", "Offer", "Rejected"],
    "Under Review" => ["Shortlisted", "Interview Scheduled", "Offer", "Rejected"],
    "Shortlisted" => ["Interview Scheduled", "Offer", "Rejected"],
    "Interview Scheduled" => ["Offer", "Rejected"],
    "Offer" => ["Hired", "Rejected"],
    "Rejected" => [],
    "Hired" => []
  }.freeze

  belongs_to :job
  belongs_to :candidate, class_name: "User"
  attribute :screening_answers, :json, default: -> { [] }
  validates :candidate_id, uniqueness: { scope: :job_id }
  has_many :application_events, dependent: :destroy

  def can_transition_to?(next_status)
    next_status == status || STATUS_TRANSITIONS.fetch(status, []).include?(next_status)
  end

  def api_json
    attributes.merge(jobId: job_id, coverLetter: cover_letter, interviewDate: interview_date,
      createdAt: created_at, updatedAt: updated_at, screeningAnswers: screening_answers,
      opportunityKind: job.opportunity_kind, workplace: job.workplace,
      title: job.title, company: job.company, location: job.location)
  end
end
