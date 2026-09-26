class JobsController < ApplicationController
  def index
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
    if params[:status] != "draft" && current_user.jobs.where(status: %w[pending published]).count >= active_post_limit
      return render_error("Your plan limit has been reached. Upgrade to continue.", :payment_required, "PLAN_LIMIT")
    end
    flags = moderation_flags
    job = current_user.jobs.create!(job_params.merge(status: params[:status] == "draft" ? "draft" : "pending", company: params[:company].presence || current_user.profile&.company_name || current_user.name, moderation_note: flags.join("; ").presence))
    audit!("job.create", job)
    render json: { id: job.id, status: job.status, moderationFlags: flags }, status: :created
  end

  def apply
    return unless authenticate!("jobseeker")
    job = Job.published.find(params[:id])
    return render_error("You cannot apply to an opportunity you created.", :conflict) if job.employer_id == current_user.id
    return render_error("The application deadline has passed.", :conflict) if job.application_deadline&.past?
    return render_error("This opportunity requires at least one portfolio item.", :conflict) if job.portfolio_required? && current_user.portfolio_items.none?
    application = job.applications.create!(candidate: current_user, cover_letter: params[:coverLetter], screening_answers: params[:screeningAnswers] || [])
    application.application_events.create!(actor: current_user, event_type: "created", to_status: "Applied")
    Notification.create!(user: job.employer, kind: "application", title: "New application", body: "#{current_user.name} applied to #{job.title}.", link: "/hiring/applicants")
    audit!("application.create", application)
    render json: { id: application.id, status: application.status }, status: :created
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
    return render_error("You have already applied to this opportunity.", :conflict) if error.to_s.include?("Candidate") || error.to_s.include?("unique")
    raise
  end

  def saved
    return unless authenticate!("jobseeker")
    render json: { jobs: Job.joins(:saved_jobs).where(saved_jobs: { user_id: current_user.id }).with_applications_count.includes(employer: :profile).order("saved_jobs.created_at DESC").map(&:api_json) }
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

  private

  def job_params
    raw = params.permit(:title, :location, :type, :genre, :salary, :description, :requirements, :experienceLevel,
      :opportunityKind, :functionArea, :workplace, :compensationMin, :compensationMax, :currency,
      :compensationPeriod, :paid, :applicationDeadline, :startDate, :duration, :portfolioRequired, :slots,
      skills: [], languages: [], screeningQuestions: []).to_h
    mapped = raw.transform_keys { _1.underscore }
    mapped["kind"] = mapped.delete("type") || "Project-based"
    mapped["genre"] = "Multi-genre" if mapped["genre"].blank?
    mapped["opportunity_kind"] ||= "job"
    mapped["workplace"] ||= "onsite"
    mapped["currency"] ||= "INR"
    mapped
  end

  def active_post_limit
    code = Subscription.where(user: current_user, status: %w[active trialing]).order(created_at: :desc).pick(:plan_code) || "free"
    { "free" => 1, "pro" => 10, "studio" => 50, "enterprise" => 9999 }.fetch(code, 1)
  end

  def moderation_flags
    text = [params[:title], params[:description], params[:requirements]].join(" ").downcase
    flags = []
    flags << "Potential off-platform or fee language" if text.match?(/whatsapp|telegram|pay.*fee|registration fee|security deposit/)
    flags << "Compensation not disclosed" if params[:salary].blank? && params[:compensationMin].blank? && params[:compensationMax].blank?
    flags << "Description is very short" if params[:description].to_s.length < 80
    flags
  end
end
