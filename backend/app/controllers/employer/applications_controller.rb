module Employer
  class ApplicationsController < ApplicationController
    def index
      return unless authenticate!("jobseeker", "employer")
      scope = Application.joins(:job).includes(:job, candidate: :profile).where(jobs: { employer_id: current_user.id })
      scope = scope.where(job_id: params[:jobId]) if params[:jobId].present?
      rows = scope.order(updated_at: :desc).map do |application|
        application.api_json.merge(jobTitle: application.job.title, candidateId: application.candidate_id,
          candidateName: application.candidate.name, candidateEmail: application.candidate.email,
          headline: application.candidate.profile&.headline, candidateLocation: application.candidate.profile&.location,
          skills: application.candidate.profile&.skills || [], genres: application.candidate.profile&.genres || [],
          verified: application.candidate.profile&.verified || false)
      end
      render json: { applications: rows }
    end

    def update
      return unless authenticate!("jobseeker", "employer")
      application = Application.joins(:job).where(jobs: { employer_id: current_user.id }).find(params[:id])
      allowed = ["Applied", "Under Review", "Shortlisted", "Interview Scheduled", "Offer", "Rejected", "Hired"]
      return render_error("Invalid application status.", :bad_request) unless allowed.include?(params[:status])
      from = application.status
      application.update!(status: params[:status], interview_date: params[:interviewDate], recruiter_rating: params[:recruiterRating] || application.recruiter_rating, recruiter_note: params[:recruiterNote] || application.recruiter_note)
      Notification.create!(user: application.candidate, kind: "application_status", title: "Application update", body: "#{application.job.title}: #{application.status}", link: "/jobseeker/applications")
      audit!("application.status", application, from:, to: application.status)
      render json: { ok: true }
    end
  end
end
