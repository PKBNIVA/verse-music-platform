class JobsController < ApplicationController
  include JobAuthoring
  FILTER_PARAMS = %i[q location kind function workplace experience paid verified].freeze
  LIST_LIMIT = 200

  def index
    # ?location[]=a or ?kind[x]=y arrive as arrays/hashes; the filters below expect text.
    if (bad = FILTER_PARAMS.find { params.key?(_1) && !params[_1].is_a?(String) })
      return render_error("Search filter \"#{bad}\" must be a single text value.", :bad_request, "INVALID_FILTER")
    end
    jobs = Job.published.with_applications_count.includes(employer: :profile).order(featured: :desc, created_at: :desc)
    query = params[:q].to_s.strip
    if query.present?
      q = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      jobs = jobs.where(<<~SQL.squish, q:)
        jobs.title ILIKE :q OR jobs.company ILIKE :q OR jobs.description ILIKE :q OR
        jobs.requirements ILIKE :q OR jobs.genre ILIKE :q OR jobs.function_area ILIKE :q OR
        jobs.opportunity_kind ILIKE :q OR jobs.skills::text ILIKE :q
      SQL
    end
    jobs = jobs.where("jobs.location ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:location])}%") if params[:location].present?
    { kind: :opportunity_kind, function: :function_area, workplace: :workplace, experience: :experience_level }.each { |key, column| jobs = jobs.where(column => params[key]) if params[key].present? }
    jobs = jobs.where(paid: true) if params[:paid] == "true"
    jobs = jobs.joins(employer: :profile).where(profiles: { verified: true }) if params[:verified] == "true"
    saved = current_user&.jobseeker? ? SavedJob.where(user: current_user).pluck(:job_id).to_set : Set.new
    render json: { jobs: jobs.limit(250).map { |job| job.api_json.merge(saved: saved.include?(job.id)) } }
  end

  def show
    job = Job.with_applications_count.includes(employer: :profile).find(params[:id])
    unless job.published? || current_user&.admin? || current_user&.id == job.employer_id
      return render_error("Opportunity not found", :not_found)
    end
    applied = current_user&.jobseeker? && Application.exists?(candidate: current_user, job:)
    saved = current_user&.jobseeker? && SavedJob.exists?(user: current_user, job:)
    render json: { job: job.api_json.merge(applied:, saved:) }
  end

  def create
    return unless authenticate!("jobseeker", "employer")
    return unless require_scalar_params!(:status, :company)
    draft = params[:status] == "draft"
    attributes = job_params(defaults: true)
    flags = moderation_flags_for(attributes)
    job = current_user.jobs.build(attributes.merge(status: draft ? "draft" : "pending", company: params[:company].presence || current_user.profile&.company_name || current_user.name, moderation_note: flags.join("; ").presence))
    return render_error(job.errors.full_messages.to_sentence, :unprocessable_entity) unless job.valid?
    if !draft && (error = submission_error(job))
      return render_error(error, :unprocessable_entity)
    end
    Job.transaction do
      if !draft && (limit_error = active_post_limit_error)
        render_error(limit_error, :payment_required, "PLAN_LIMIT")
        raise ActiveRecord::Rollback
      end
      job.save!
    end
    return if performed?
    audit!("job.create", job)
    render json: { id: job.id, status: job.status, moderationFlags: flags }, status: :created
  end

  def apply
    return unless authenticate!("jobseeker")
    job = Job.published.find(params[:id])
    return render_error("You cannot apply to an opportunity you created.", :conflict) if job.employer_id == current_user.id
    return render_error("The application deadline has passed.", :conflict) if job.application_deadline&.past?
    return render_error("This opportunity requires at least one portfolio item.", :conflict) if job.portfolio_required? && current_user.portfolio_items.none?
    cover_letter = params[:coverLetter]
    return render_error("The note to the employer must be text.", :unprocessable_entity) unless cover_letter.nil? || cover_letter.is_a?(String)
    return render_error("The note to the employer must be 5,000 characters or fewer.", :unprocessable_entity) if cover_letter.to_s.length > 5_000
    answers = params[:screeningAnswers]
    answers = Array(answers.is_a?(Array) ? answers : nil).select { _1.is_a?(String) }.map { _1.first(5_000) }
    application = job.applications.create!(candidate: current_user, cover_letter: cover_letter.presence, screening_answers: answers)
    application.application_events.create!(actor: current_user, event_type: "created", to_status: "Applied")
    Notifier.new_application(application)
    audit!("application.create", application)
    render json: { id: application.id, status: application.status }, status: :created
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    return render_error("You have already applied to this opportunity.", :conflict) if error.to_s.include?("Candidate") || error.to_s.include?("unique")
    raise
  end

  def saved
    return unless authenticate!("jobseeker")
    render json: { jobs: Job.joins(:saved_jobs).where(saved_jobs: { user_id: current_user.id }).with_applications_count.includes(employer: :profile).order("saved_jobs.created_at DESC").limit(LIST_LIMIT).map(&:api_json) }
  end

  def save
    return unless authenticate!("jobseeker")
    job = Job.published.find(params[:id])
    begin
      SavedJob.find_or_create_by!(user: current_user, job:)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent request saved it first (unique index on user_id, job_id): same outcome.
    end
    render json: { ok: true }, status: :created
  end

  def unsave
    return unless authenticate!("jobseeker")
    SavedJob.where(user: current_user, job_id: params[:id]).delete_all
    render json: { ok: true }
  end
end
