class Application < ApplicationRecord
  belongs_to :job
  belongs_to :candidate, class_name: "User"
  attribute :screening_answers, :json, default: -> { [] }
  validates :candidate_id, uniqueness: { scope: :job_id }

  def api_json
    attributes.merge(jobId: job_id, coverLetter: cover_letter, interviewDate: interview_date,
      createdAt: created_at, updatedAt: updated_at, screeningAnswers: screening_answers,
      opportunityKind: job.opportunity_kind, workplace: job.workplace,
      title: job.title, company: job.company, location: job.location)
  end
end
