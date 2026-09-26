module Employer
  class ApplicationsController < ApplicationController
    include ScalarParams
    LIST_LIMIT = 200

    def index
      return unless authenticate!("jobseeker", "employer")
      return unless require_scalar_params!(:jobId)
      scope = Application.joins(:job).includes(:job, candidate: :profile).where(jobs: { employer_id: current_user.id })
      scope = scope.where(job_id: params[:jobId]) if params[:jobId].present?
      rows = scope.order(updated_at: :desc).limit(LIST_LIMIT).map do |application|
        application.api_json.merge(jobTitle: application.job.title, candidateId: application.candidate_id,
          candidateName: application.candidate.name, candidateEmail: application.candidate.email,
          headline: application.candidate.profile&.headline, candidateLocation: application.candidate.profile&.location,
          experience: application.candidate.profile&.experience,
          skills: application.candidate.profile&.skills || [], genres: application.candidate.profile&.genres || [],
          verified: application.candidate.profile&.verified || false,
          allowedNextStatuses: Application::STATUS_TRANSITIONS.fetch(application.status, []))
      end
      render json: { applications: rows }
    end

    def update
      return unless authenticate!("jobseeker", "employer")
      return unless require_scalar_params!(:status, :interviewDate, :recruiterNote, :recruiterRating, :note)
      application = Application.joins(:job).where(jobs: { employer_id: current_user.id }).find(params[:id])
      requested_status = params[:status].presence
      if requested_status
        return render_error("Invalid application status.", :bad_request) unless Application::STATUS_TRANSITIONS.key?(requested_status)
        return render_error("Invalid application status change.", :conflict) unless application.can_transition_to?(requested_status)
        return render_error("Interview date is required.", :unprocessable_entity) if requested_status == "Interview Scheduled" && params[:interviewDate].blank?
      end

      rating = params[:recruiterRating]
      if rating.present? && !rating.to_s.match?(/\A[1-5]\z/)
        return render_error("Recruiter rating must be between 1 and 5.", :unprocessable_entity)
      end
      if requested_status.blank? && !params.key?(:recruiterNote) && !params.key?(:recruiterRating)
        return render_error("No application changes supplied.", :bad_request)
      end

      from = application.status
      Application.transaction do
        changes = {}
        changes[:status] = requested_status if requested_status
        changes[:interview_date] = params[:interviewDate] if requested_status == "Interview Scheduled"
        changes[:recruiter_rating] = rating if params.key?(:recruiterRating)
        changes[:recruiter_note] = params[:recruiterNote] if params.key?(:recruiterNote)
        application.update!(changes)
        if requested_status
          application.application_events.create!(actor: current_user, event_type: "status_changed", from_status: from, to_status: application.status, note: params[:note])
          Notifier.application_status(application)
        else
          application.application_events.create!(actor: current_user, event_type: "recruiter_annotation", from_status: from, to_status: from)
        end
      end
      audit!(requested_status ? "application.status" : "application.annotation", application, from:, to: application.status)
      render json: { ok: true, application: application.api_json.merge(allowedNextStatuses: Application::STATUS_TRANSITIONS.fetch(application.status, [])) }
    end
  end
end
