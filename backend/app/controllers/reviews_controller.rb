class ReviewsController < ApplicationController
  def index
    scope = Review.includes(:author, :employer).where(status: "published")
    scope = scope.where(employer_id: params[:employerId]) if params[:employerId].present?
    render json: { reviews: scope.order(created_at: :desc).map { _1.attributes.merge(authorName: _1.author.name, employerName: _1.employer.profile&.company_name || _1.employer.name) } }
  end

  def create
    return unless authenticate!("jobseeker")
    employer = User.employer.active.find(params[:employerId])
    worked_together = Application.joins(:job).exists?(candidate_id: current_user.id, status: "Hired", jobs: { employer_id: employer.id })
    return render_error("You can review an employer only after a completed hire.", :forbidden, "REVIEW_NOT_ELIGIBLE") unless worked_together
    review = Review.create!(author: current_user, employer:, rating: params[:rating], title: params[:title], body: params[:body], status: "pending")
    render json: { id: review.id }, status: :created
  end
end
