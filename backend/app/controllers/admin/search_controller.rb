module Admin
  class SearchController < BaseController
    def reindex
      count = Job.published.count + User.jobseeker.active.where(profile_complete: true).count
      render json: { count:, indexed: count, provider: "postgresql" }
    end
  end
end
