module Admin
  class ReviewsController < BaseController
    def index = render(json: { reviews: Review.includes(:author, :employer).order(created_at: :desc).map { _1.attributes.merge(authorName: _1.author.name, employerName: _1.employer.profile&.company_name || _1.employer.name) } })
    def update
      return render_error("Invalid review status.", :bad_request) unless %w[published rejected].include?(params[:status])
      review = Review.find(params[:id]); review.update!(status: params[:status]); audit!("admin.review.status", review); render json: { ok: true }
    end
  end
end
