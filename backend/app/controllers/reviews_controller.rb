class ReviewsController < ApplicationController
  def index
    scope = Review.includes(:author, :employer).where(status: "published")
    scope = scope.where(employer_id: params[:employerId]) if params[:employerId].present?
    payload = { reviews: scope.order(created_at: :desc).map { _1.attributes.merge(authorName: _1.author.name, employerName: _1.employer.profile&.company_name || _1.employer.name) } }
    payload[:eligibleEmployers] = eligible_employers.map { public_employer(_1).merge(eligibleForReview: true) } if current_user&.jobseeker?
    render json: payload
  end

  def create
    return unless authenticate!("jobseeker")
    employer = User.employer.active.find(params[:employerId])
    worked_together = eligible_employers.exists?(id: employer.id)
    return render_error("You can review an employer only after a completed hire.", :forbidden, "REVIEW_NOT_ELIGIBLE") unless worked_together
    review = Review.create!(author: current_user, employer:, rating: params[:rating], title: params[:title], body: params[:body], status: "pending")
    render json: { id: review.id }, status: :created
  end

  private

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
