class BandProjectsController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }
  def index = render(json: { projects: current_user.band_projects.includes(:band_project_roles).order(updated_at: :desc).map { _1.attributes.merge(roles: _1.band_project_roles) } })
  def create
    project = current_user.band_projects.create!(name: params[:name], concept: params[:concept], city: params[:city], genres: params[:genres] || [], commitment_type: params[:commitmentType].presence || "project", rehearsal_schedule: params[:rehearsalSchedule], compensation_model: params[:compensationModel], status: "open"); render json: { id: project.id }, status: :created
  end
  def add_role
    project = current_user.band_projects.find(params[:id]); role = project.band_project_roles.create!(role_name: params[:roleName], instrument: params[:instrument], count_needed: params[:countNeeded] || 1, skill_level: params[:skillLevel].presence || "professional", requirements: params[:requirements], compensation: params[:compensation], status: "open"); render json: { id: role.id }, status: :created
  end
  def publish_role
    project = current_user.band_projects.find(params[:id]); role = project.band_project_roles.find(params[:roleId]); return render_error("Role already published", :conflict) if role.opportunity_id.present?
    return render_error("Your plan limit has been reached. Upgrade to continue.", :payment_required, "PLAN_LIMIT") if current_user.jobs.where(status: %w[pending published]).count >= active_post_limit
    description = "#{project.concept}\n\nRole: #{role.role_name}. #{role.requirements}".strip.ljust(60, ".")
    job = current_user.jobs.create!(title: "#{role.role_name} — #{project.name}", company: current_user.profile&.company_name || project.name, location: project.city.presence || "Flexible", kind: "Project-based", genre: project.genres.first || "Multi-genre", description:, requirements: role.requirements, skills: [role.role_name, role.instrument].compact, status: "pending", opportunity_kind: "collaboration", function_area: "Performance", workplace: "onsite", currency: "INR", paid: !role.compensation.to_s.match?(/unpaid/i), slots: role.count_needed)
    role.update!(opportunity: job, status: "published"); render json: { jobId: job.id, status: job.status }, status: :created
  end

  private

  def active_post_limit
    Entitlements.for(current_user).limit(:active_posts)
  end
end
