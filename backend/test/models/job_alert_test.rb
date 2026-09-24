require "test_helper"

class JobAlertTest < ActiveSupport::TestCase
  setup do
    @candidate = User.create!(name: "Alert Candidate", email: "alert-model@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    @employer = User.create!(name: "Alert Studio", email: "alert-studio@example.com", password: "StrongPass123!", role: "employer", status: "active")
  end

  test "daily and weekly alerts schedule delivery while saved filters do not" do
    travel_to Time.zone.parse("2026-09-24 10:00:00") do
      daily = @candidate.job_alerts.create!(name: "Daily", frequency: "daily")
      weekly = @candidate.job_alerts.create!(name: "Weekly", frequency: "weekly")
      saved = @candidate.job_alerts.create!(name: "Saved", frequency: "saved")

      assert_equal 1.day.from_now, daily.next_run_at
      assert_equal 1.week.from_now, weekly.next_run_at
      assert_nil saved.next_run_at
    end
  end

  test "matching jobs applies all alert filters and publication window" do
    alert = @candidate.job_alerts.create!(name: "Tour", query: "guitar", location: "Mumbai", opportunity_kind: "gig", function_area: "Performance", remote_only: true, frequency: "daily")
    matching = create_job(title: "Tour Guitarist", published_at: 1.hour.ago, workplace: "remote")
    create_job(title: "Tour Drummer", published_at: 1.hour.ago, workplace: "remote")
    create_job(title: "Tour Guitarist", published_at: 2.days.ago, workplace: "remote")
    create_job(title: "Tour Guitarist", published_at: 1.hour.ago, workplace: "onsite")

    assert_equal [matching.id], alert.matching_jobs(window_start: 1.day.ago, window_end: Time.current).pluck(:id)
  end

  private

  def create_job(title:, published_at:, workplace:)
    @employer.jobs.create!(title:, company: "Alert Studio", location: "Mumbai", kind: "Gig", genre: "Rock", description: "A sufficiently detailed opportunity description for a professional touring musician.", status: "published", opportunity_kind: "gig", function_area: "Performance", workplace:, published_at:)
  end
end
