module Admin
  class SearchController < BaseController
    def reindex = render(json: { indexed: Job.published.count + User.jobseeker.active.where(profile_complete: true).count, provider: "postgresql" })
  end
end
