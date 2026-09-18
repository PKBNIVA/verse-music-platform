class ReviewsController < ApplicationController
  def index
    scope = Review.includes(:author, :employer).where(status: "published")
    scope = scope.where(employer_id: params[:employerId]) if params[:employerId].present?
    render json: { reviews: scope.order(created_at: :desc).map { _1.attributes.merge(authorName: _1.author.name, employerName: _1.employer.profile&.company_name || _1.employer.name) } }
  end

  def create
    return unless authenticate!("jobseeker")
    review = Review.create!(author: current_user, employer_id: params[:employerId], rating: params[:rating], title: params[:title], body: params[:body], status: "pending")
    render json: { id: review.id }, status: :created
  end
end
