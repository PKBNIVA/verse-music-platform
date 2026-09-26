class ReviewsController < ApplicationController
  def index
    return render_invalid_employer if params.key?(:employerId) && !params[:employerId].is_a?(String)
    scope = Review.includes(:author, :employer).where(status: "published")
    scope = scope.where(employer_id: params[:employerId]) if params[:employerId].present?
    payload = { reviews: scope.order(created_at: :desc).limit(200).map { _1.attributes.merge(authorName: _1.author.name, employerName: _1.employer.profile&.company_name || _1.employer.name) } }
    payload[:eligibleEmployers] = eligible_employers.map { public_employer(_1).merge(eligibleForReview: true) } if current_user&.jobseeker?
    render json: payload
  end

  def create
    return unless authenticate!("jobseeker")
    return render_invalid_employer unless params[:employerId].is_a?(String)
    employer = User.employer.active.find(params[:employerId])
    outcome = Review.transaction do
      # reviews has no unique (author_id, employer_id) index, so concurrent submissions are
      # serialized per pair with a transaction-scoped advisory lock instead.
      lock_key = Review.lease_connection.quote("review:#{current_user.id}:#{employer.id}")
      Review.lease_connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{lock_key}))")
      if Review.exists?(author_id: current_user.id, employer_id: employer.id)
        :duplicate
      elsif !eligible_employers.exists?(id: employer.id)
        :ineligible
      else
        Review.create!(author: current_user, employer:, rating: params[:rating], title: params[:title], body: params[:body], status: "pending")
      end
    end
    return render_error("You have already reviewed this employer.", :conflict, "REVIEW_EXISTS") if outcome == :duplicate
    return render_error("You can review an employer only after a completed hire.", :forbidden, "REVIEW_NOT_ELIGIBLE") if outcome == :ineligible
    render json: { id: outcome.id }, status: :created
  end

  private

  def render_invalid_employer
    render_error("employerId must be a single employer id.", :unprocessable_content, "INVALID_EMPLOYER")
  end

  # Shared by the form response and create authorization to prevent contract drift.
  def eligible_employers
    reviewed_ids = Review.where(author_id: current_user.id).select(:employer_id)
    User.employer.active
      .joins(jobs: :applications)
      .where(applications: { candidate_id: current_user.id, status: "Hired" })
      .where.not(id: reviewed_ids)
      .includes(:profile)
      .distinct
  end
end
