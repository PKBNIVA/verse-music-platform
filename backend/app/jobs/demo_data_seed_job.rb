# Seeds one publicly visible demo batch (see SyntheticQa::Demo). Enqueued by
# Admin::DemoDataController; progress is recorded through SyntheticQa::DemoJobs.
class DemoDataSeedJob < ApplicationJob
  queue_as :default

  def perform(batch:, size:, admin_id:)
    SyntheticQa::DemoJobs.record!(job_id, "running", actor_id: admin_id)
    counts = SyntheticQa::Demo::SIZES.fetch(size)
    admin = User.admin.active.find(admin_id)
    result = SyntheticQa::BatchSeeder.call(batch:, jobseekers: counts[:jobseekers], employers: counts[:employers], authorized_by: admin)
    SyntheticQa::DemoJobs.record!(job_id, "succeeded", actor_id: admin_id, result: result.to_h.except(:batch))
  rescue StandardError => error
    Rails.logger.error({ event: "demo_data.seed_failed", jobId: job_id, batch:, error: error.class.name }.to_json)
    SyntheticQa::DemoJobs.record!(job_id, "failed", actor_id: admin_id, error: error.message.first(300))
  end
end
