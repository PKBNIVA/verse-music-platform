module Employer
  # The poster's own opportunities: list, edit fields and move between owner-controlled statuses.
  class JobsController < ApplicationController
    include JobAuthoring

    # Owner-initiated status changes. Publishing is the moderator's decision (admin/jobs).
    OWNER_TRANSITIONS = {
      "draft" => %w[pending closed],
      "pending" => %w[draft closed],
      "published" => %w[closed],
      "rejected" => %w[draft pending closed],
      "closed" => %w[pending draft]
    }.freeze

    def index
      return unless authenticate!("jobseeker", "employer")
      jobs = current_user.jobs.with_applications_count.includes(employer: :profile).order(updated_at: :desc).limit(200)
      render json: { jobs: jobs.map { owner_json(_1) } }
    end

    def update
      return unless authenticate!("jobseeker", "employer")
      return unless require_scalar_params!(:status, :company)
      job = current_user.jobs.find(params[:id])
      requested = params[:status].presence
      if requested
        return render_error("Invalid opportunity status.", :bad_request) unless OWNER_TRANSITIONS.key?(requested)
        if requested != job.status && !OWNER_TRANSITIONS.fetch(job.status, []).include?(requested)
          return render_error("An opportunity that is #{job.status} cannot be moved to #{requested}.", :conflict)
        end
      end

      attributes = job_params
      return render_error("No opportunity changes supplied.", :bad_request) if requested.nil? && attributes.empty? && params[:company].blank?
      edited = attributes.any? { |key, value| job.public_send(key) != job.class.type_for_attribute(key).cast(value) }
      if edited && job.closed? && requested.nil?
        return render_error("Reopen or save this opportunity as a draft to edit it.", :conflict)
      end
      job.assign_attributes(attributes)
      job.company = params[:company] if params[:company].present?
      # A live listing that changes goes back to review so moderated content stays moderated.
      target = requested || ((job.published? || job.rejected?) && edited ? "pending" : job.status)
      job.status = target
      if edited
        flags = moderation_flags_for(job.attributes)
        job.moderation_note = flags.join("; ").presence
      end
      return render_error(job.errors.full_messages.to_sentence, :unprocessable_content) unless job.valid?
      if target == "pending" && (error = submission_error(job))
        return render_error(error, :unprocessable_content)
      end

      Job.transaction do
        if target == "pending" && !JobAuthoring::ACTIVE_STATUSES.include?(job.status_in_database) && (limit_error = active_post_limit_error(except: job))
          render_error(limit_error, :payment_required, "PLAN_LIMIT")
          raise ActiveRecord::Rollback
        end
        job.save!
      end
      return if performed?
      audit!(edited ? "job.update" : "job.status", job, status: job.status)
      render json: { ok: true, job: owner_json(job.reload) }
    end

    private

    def owner_json(job)
      job.api_json.merge("applications" => job.applications_count, "allowedNextStatuses" => OWNER_TRANSITIONS.fetch(job.status, []))
    end
  end
end
