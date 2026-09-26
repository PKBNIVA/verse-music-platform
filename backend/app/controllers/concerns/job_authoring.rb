# Shared by job creation (JobsController#create) and owner edits (Employer::JobsController#update):
# the permitted job fields, moderation flags and the active-post plan limit.
module JobAuthoring
  extend ActiveSupport::Concern
  include ScalarParams

  JOB_FIELDS = %i[title location type genre salary description requirements experienceLevel opportunityKind functionArea
    workplace compensationMin compensationMax currency compensationPeriod paid applicationDeadline startDate duration
    portfolioRequired slots].freeze
  # Jobs counted against the plan's `active_posts` limit.
  ACTIVE_STATUSES = %w[pending published].freeze

  private

  # Only the keys present in the request, mapped to column names. `defaults: true` fills the
  # values a brand-new job needs.
  def job_params(defaults: false)
    raw = params.permit(*JOB_FIELDS, skills: [], languages: [], screeningQuestions: []).to_h
    mapped = raw.transform_keys { _1.underscore }
    mapped["kind"] = mapped.delete("type") if mapped.key?("type")
    # Columns are NOT NULL; a draft may leave them blank until it is submitted.
    %w[title location description].each { |key| mapped[key] = mapped[key].to_s.strip if mapped.key?(key) }
    mapped["genre"] = "Multi-genre" if mapped.key?("genre") && mapped["genre"].blank?
    if defaults
      mapped["kind"] = "Project-based" if mapped["kind"].blank?
      mapped["genre"] ||= "Multi-genre"
      mapped["opportunity_kind"] ||= "job"
      mapped["workplace"] ||= "onsite"
      mapped["currency"] ||= "INR"
      %w[location description].each { |key| mapped[key] ||= "" }
      # The columns default to 1, which would read as a disclosed (and nonsensical) rate.
      %w[compensation_min compensation_max].each { |key| mapped[key] = nil unless mapped.key?(key) }
    end
    mapped
  end

  # `attrs` uses column names (string keys): a job's attributes or the output of job_params.
  def moderation_flags_for(attrs)
    title, description, requirements, salary, compensation_min, compensation_max =
      attrs.values_at("title", "description", "requirements", "salary", "compensation_min", "compensation_max")
    text = [title, description, requirements].join(" ").downcase
    flags = []
    flags << "Potential off-platform or fee language" if text.match?(/whatsapp|telegram|pay.*fee|registration fee|security deposit/)
    flags << "Compensation not disclosed" if salary.blank? && compensation_min.blank? && compensation_max.blank?
    flags << "Description is very short" if description.to_s.length < 80
    flags
  end

  # Returns an error message when the job cannot be submitted for review as it stands.
  def submission_error(job)
    return "The application deadline must be in the future." if job.application_deadline.present? && job.application_deadline.past?
    nil
  end

  # Call inside a transaction: locks the owner so concurrent submissions cannot exceed the plan.
  def active_post_limit_error(except: nil)
    current_user.lock!
    active = current_user.jobs.where(status: ACTIVE_STATUSES)
    active = active.where.not(id: except.id) if except
    limit = Entitlements.for(current_user).limit(:active_posts)
    return nil if active.count < limit
    "Your plan allows #{limit} active #{'opportunity'.pluralize(limit)}. Close one or upgrade your plan to continue."
  end
end
