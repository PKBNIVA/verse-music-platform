class JobAlertSweepJob < ApplicationJob
  queue_as :scheduled

  def perform(now = Time.current)
    JobAlert.due_at(now).find_each do |alert|
      alert.with_lock do
        next unless alert.active? && alert.next_run_at && alert.next_run_at <= now

        window_start = alert.last_run_at || alert.created_at
        alert.update!(last_run_at: now, next_run_at: alert.next_delivery_after(now))
        JobAlertDeliveryJob.perform_later(alert.id, window_start, now)
      end
    end
  end
end
