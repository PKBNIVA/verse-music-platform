require "test_helper"

class JobAlertJobsTest < ActiveJob::TestCase
  setup do
    @candidate = User.create!(name: "Alert Recipient", email: "alert-jobs@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    @employer = User.create!(name: "Alert Employer", email: "alert-employer@example.com", password: "StrongPass123!", role: "employer", status: "active")
    @alert = @candidate.job_alerts.create!(name: "Fresh work", frequency: "daily", active: true)
    @job = @employer.jobs.create!(title: "Session Guitarist", company: "Verse Studio", location: "Mumbai", kind: "Project", genre: "Rock", description: "A sufficiently detailed opportunity description for an experienced session guitarist.", status: "published", published_at: 1.hour.ago)
  end

  test "delivery creates one notification per alert and job even when retried" do
    window_start = 1.day.ago
    2.times { JobAlertDeliveryJob.perform_now(@alert.id, window_start, Time.current) }

    assert_equal 1, JobAlertDelivery.where(job_alert: @alert, job: @job).count
    assert_equal 1, @candidate.notifications.where(kind: "job_alert").count
  end

  test "sweep advances due alert and enqueues a bounded delivery window" do
    now = Time.current.change(usec: 0)
    @alert.update_columns(last_run_at: now - 1.day, next_run_at: now - 1.minute)

    assert_enqueued_with(job: JobAlertDeliveryJob, args: [@alert.id, now - 1.day, now]) do
      JobAlertSweepJob.perform_now(now)
    end

    assert_equal now, @alert.reload.last_run_at
    assert_equal now + 1.day, @alert.next_run_at
  end

  test "sweep skips paused and saved alerts" do
    @alert.update!(active: false)
    saved = @candidate.job_alerts.create!(name: "Stored search", frequency: "saved", active: true)

    assert_no_enqueued_jobs only: JobAlertDeliveryJob do
      JobAlertSweepJob.perform_now
    end
    assert_nil saved.reload.last_run_at
  end
end
