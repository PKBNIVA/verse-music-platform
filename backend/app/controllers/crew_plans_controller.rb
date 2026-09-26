class CrewPlansController < ApplicationController
  include ScalarParams
  before_action -> { authenticate!("jobseeker", "employer") }
  CREW = { "music" => [["Performance", "Music Director"], ["Performance", "Performers"]], "sound" => [["Audio", "FOH Engineer"], ["Audio", "Monitor Engineer"]], "lighting" => [["Lighting", "Lighting Designer"], ["Lighting", "Lighting Technician"]], "video" => [["Video", "Video Director"], ["Video", "Camera Operator"]], "production" => [["Production", "Production Manager"], ["Production", "Stage Manager"]] }.freeze
  def index = render(json: { plans: current_user.crew_plans.includes(:crew_plan_roles).order(updated_at: :desc).limit(200).map { _1.attributes.merge(roles: _1.crew_plan_roles.map { |role| role.attributes.transform_keys { |key| key.camelize(:lower) } }) } })
  def create
    return unless require_scalar_params!(:title, :eventType, :city, :eventDate, :audienceSize, :budget, :currency, :notes)
    needs = string_list_param(:needs)
    genres = string_list_param(:genres)
    return render_error("needs and genres must be lists of text values.", :unprocessable_content, "INVALID_PARAMETER") if needs.nil? || genres.nil?
    event_date = params[:eventDate].presence
    if event_date && (Date.iso8601(event_date.to_s) rescue nil).nil?
      return render_error("Event date must be a valid date.", :unprocessable_content)
    end
    plan = nil
    CrewPlan.transaction do
      plan = current_user.crew_plans.create!(title: params[:title].to_s.strip, event_type: params[:eventType].presence || "Event", city: params[:city].to_s.strip, event_date:, audience_size: params[:audienceSize].presence, budget: params[:budget].presence, currency: params[:currency].presence || "INR", genres:, needs:, notes: params[:notes])
      roles = plan.needs.flat_map { CREW[_1] || [] }.uniq
      roles = CREW.values.flatten(1).first(4) if roles.empty?
      roles.each { |category, name| plan.crew_plan_roles.create!(category:, role_name: name, priority: "required", count_needed: 1, rationale: "Recommended for #{plan.event_type}") }
    end
    render json: { id: plan.id, roles: plan.crew_plan_roles.map { _1.attributes.transform_keys { |k| k.camelize(:lower) } } }, status: :created
  end
  def convert
    plan = current_user.crew_plans.find(params[:id])
    project = nil
    BandProject.transaction do
      project = current_user.band_projects.create!(name: plan.title, concept: "Crew plan for #{plan.event_type}. #{plan.notes}", city: plan.city, genres: plan.genres, commitment_type: "project", compensation_model: plan.budget ? "#{plan.currency} #{plan.budget}" : nil, status: "open")
      plan.crew_plan_roles.each { |role| project.band_project_roles.create!(role_name: role.role_name, instrument: role.instrument, count_needed: role.count_needed, skill_level: "professional", requirements: role.rationale, status: "open") }
    end
    render json: { projectId: project.id }, status: :created
  end
end
