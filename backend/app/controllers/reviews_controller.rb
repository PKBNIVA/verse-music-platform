class ReviewsController < ApplicationController
  def index
    render json: { reviews: Review.where(employer_id: params[:employerId], status: "published").order(created_at: :desc) }
  end

  def create
    return unless authenticate!("jobseeker")
    review = Review.create!(author: current_user, employer_id: params[:employerId], rating: params[:rating], title: params[:title], body: params[:body], status: "pending")
    render json: { id: review.id }, status: :created
  end
end
