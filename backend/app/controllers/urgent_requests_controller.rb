class UrgentRequestsController < ApplicationController
  before_action -> { authenticate!("jobseeker", "employer") }
  LIST_LIMIT = 200

  def index
    return render_error("Filters must be plain text.", :bad_request, "INVALID_PARAMETER") unless [params[:city], params[:role]].all? { _1.nil? || _1.is_a?(String) }
    visible = UrgentRequest.where(status: "open").where("start_at >= ?", 1.day.ago)
      .or(UrgentRequest.where(requester: current_user))
    scope = UrgentRequest.includes(:urgent_request_responses, requester: :profile).where(id: visible.select(:id)).order(start_at: :asc).limit(LIST_LIMIT)
    scope = scope.where("city ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:city])}%") if params[:city].present?
    if params[:role].present?
      role = "%#{ActiveRecord::Base.sanitize_sql_like(params[:role])}%"
      scope = scope.where("role_name ILIKE :role OR instrument ILIKE :role OR title ILIKE :role", role:)
    end
    items = scope.to_a
    responded = UrgentRequestResponse.where(user: current_user, urgent_request_id: items.map(&:id)).pluck(:urgent_request_id).to_set
    render json: { requests: items.map { |item| item.attributes.merge(requesterName: item.requester.name, requesterVerified: item.requester.profile&.verified || false, myResponse: responded.include?(item.id), responseCount: item.urgent_request_responses.size) } }
  end
  def create
    item = UrgentRequest.create!(requester: current_user, title: params[:title], role_name: params[:roleName], instrument: params[:instrument], city: params[:city], start_at: params[:startAt], end_at: params[:endAt], budget_min: params[:budgetMin], budget_max: params[:budgetMax], currency: params[:currency].presence || "INR", genre: params[:genre], requirements: params[:requirements], travel_covered: params[:travelCovered] || false, status: "open")
    render json: { id: item.id }, status: :created
  end
  def respond
    item = UrgentRequest.where(status: "open").find(params[:id]); return render_error("You cannot respond to your own request.", :conflict) if item.requester_id == current_user.id
    return render_error("Keep your note under 1,000 characters.", :unprocessable_content) if params[:message].to_s.length > 1_000
    rate = params[:rate].presence
    return render_error("Rate must be a whole number of 0 or more.", :unprocessable_content) if rate && !rate.to_s.match?(/\A\d{1,9}\z/)
    UrgentRequestResponse.upsert({ urgent_request_id: item.id, user_id: current_user.id, message: params[:message].to_s.strip.presence, rate: rate&.to_i, status: "available", created_at: Time.current, updated_at: Time.current }, unique_by: :idx_urgent_response_unique)
    Notification.create!(user: item.requester, kind: "urgent_response", title: "Availability response", body: "#{current_user.name} responded to #{item.title}.", link: "/urgent-requests")
    render json: { ok: true }, status: :created
  end
  def responses
    item = UrgentRequest.where(requester: current_user).find(params[:id]); render json: { responses: item.urgent_request_responses.includes(user: :profile).order(created_at: :desc).limit(LIST_LIMIT).map { _1.attributes.merge(name: _1.user.name, headline: _1.user.profile&.headline) } }
  end
  def update
    item = UrgentRequest.where(requester: current_user).find(params[:id]); return render_error("Invalid status", :bad_request) unless %w[filled cancelled].include?(params[:status]); item.update!(status: params[:status]); render json: { ok: true }
  end
end
