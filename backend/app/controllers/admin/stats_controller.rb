module Admin
  class StatsController < BaseController
    def index
      render json: { stats: {
        users: User.count, jobseekers: User.jobseeker.count, employers: User.employer.count,
        verified: Profile.where(verified: true).count, jobs: Job.count, liveJobs: Job.published.count,
        pendingJobs: Job.pending.count, applications: Application.count,
        hires: Application.where(status: "Hired").count, pendingReviews: Review.where(status: "pending").count,
        verificationQueue: VerificationRequest.where(status: "pending").count,
        openReports: Report.where(status: "open").count,
        messages: Message.count, acts: Act.where(status: "active").count, bookings: BookingRequest.count,
        acceptedBookings: BookingRequest.where(status: "accepted").count,
        paidDeposits: BookingPayment.where(status: "paid", kind: "deposit").count,
        activeSubscriptions: Subscription.where(status: %w[active trialing]).where.not(plan_code: "free").count,
        trialingSubscriptions: Subscription.where(status: "trialing").count
      } }
    end
  end
end
