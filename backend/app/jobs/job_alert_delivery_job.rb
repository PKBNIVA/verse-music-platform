class JobAlertDeliveryJob < ApplicationJob
  queue_as :notifications

  def perform(alert_id, window_start, window_end)
    alert = JobAlert.find_by(id: alert_id)
    return unless alert

    alert.matching_jobs(window_start:, window_end:).find_each do |job|
      JobAlertDelivery.transaction do
        next if JobAlertDelivery.exists?(job_alert: alert, job:)

        notification = Notification.create!(
          user: alert.user,
          kind: "job_alert",
          title: "New match for #{alert.name}",
          body: "#{job.title} at #{job.company} matches your saved alert.",
          link: "/jobs/#{job.id}"
        )
        JobAlertDelivery.create!(job_alert: alert, job:, notification:)
      end
    rescue ActiveRecord::RecordNotUnique
      # Another worker delivered this alert/job pair first.
    end
  end
end
