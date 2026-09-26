# Deletes demo batches and their complete relationship graph in one transaction.
# Only batches named "demo-*" are ever touched; untagged users never are.
class DemoDataPurgeJob < ApplicationJob
  queue_as :default

  # batches: nil purges every demo batch that exists when the job runs.
  def perform(admin_id:, batches: nil)
    SyntheticQa::DemoJobs.record!(job_id, "running", actor_id: admin_id)
    admin = User.admin.active.find(admin_id)
    targets = batches.nil? ? SyntheticQa::Demo.batch_names : Array(batches)
    raise ArgumentError, "Only demo-* batches can be purged here." unless targets.all? { SyntheticQa::Demo.batch?(_1) }

    results = ApplicationRecord.transaction do
      targets.map { SyntheticQa::BatchCleanup.call(batch: _1, authorized_by: admin) }
    end
    SyntheticQa::DemoJobs.record!(job_id, "succeeded", actor_id: admin_id, result: {
      batches: targets, usersRemoved: results.sum(&:users_removed), recordsRemoved: results.sum(&:records_removed)
    })
  rescue StandardError => error
    Rails.logger.error({ event: "demo_data.purge_failed", jobId: job_id, error: error.class.name }.to_json)
    SyntheticQa::DemoJobs.record!(job_id, "failed", actor_id: admin_id, error: error.message.first(300))
  end
end
