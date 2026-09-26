require "test_helper"
require_relative "../synthetic_trace_assertions"

class DemoDataJobsTest < ActiveJob::TestCase
  include SyntheticTraceAssertions

  setup do
    @admin = User.create!(name: "Ops Admin", email: "demo-jobs-admin@example.com", password: "StrongPass123!", role: "admin", status: "active")
  end

  test "seed job creates a demo batch and records running then succeeded" do
    job = DemoDataSeedJob.new(batch: "demo-20260926-1200", size: "small", admin_id: @admin.id)
    job.perform_now
    states = AuditLog.where(entity_id: job.job_id).order(:created_at).pluck(:action)
    assert_equal %w[demo_data.job.running demo_data.job.succeeded], states
    summary = SyntheticQa::DemoJobs.find(job.job_id)
    assert_equal 20, summary.dig(:result, "jobseekers")
    assert_equal 8, summary.dig(:result, "employers")
    assert_equal 28, User.synthetic("demo-20260926-1200").count
  ensure
    SyntheticQa::BatchCleanup.call(batch: "demo-20260926-1200")
  end

  test "seed job records a failure instead of raising and never creates partial data" do
    SyntheticQa::BatchSeeder.call(batch: "demo-20260926-1300", jobseekers: 100, employers: 1)
    job = DemoDataSeedJob.new(batch: "demo-20260926-1301", size: "large", admin_id: @admin.id)
    job.perform_now
    summary = SyntheticQa::DemoJobs.find(job.job_id)
    assert_equal "failed", summary[:state]
    assert_match(/capped at 300/, summary[:error])
    assert_equal 0, User.synthetic("demo-20260926-1301").count
  ensure
    SyntheticQa::BatchCleanup.call(batch: "demo-20260926-1300")
  end

  test "seed job refuses a non-admin requester" do
    artist = User.create!(name: "Artist", email: "demo-jobs-artist@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    job = DemoDataSeedJob.new(batch: "demo-20260926-1400", size: "small", admin_id: artist.id)
    job.perform_now
    assert_equal "failed", SyntheticQa::DemoJobs.find(job.job_id)[:state]
    assert_equal 0, User.synthetic("demo-20260926-1400").count
  end

  test "purge-all job removes every demo batch completely and leaves other data alone" do
    control = User.create!(name: "Control", email: "demo-jobs-control@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    SyntheticQa::BatchSeeder.call(batch: "demo-20260926-1500", jobseekers: 20, employers: 8)
    SyntheticQa::BatchSeeder.call(batch: "demo-20260926-1501", jobseekers: 4, employers: 2)
    SyntheticQa::BatchSeeder.call(batch: "qa-keep-me", jobseekers: 2, employers: 1)
    user_ids = SyntheticQa::Demo.users.pluck(:id)

    job = DemoDataPurgeJob.new(admin_id: @admin.id)
    job.perform_now
    summary = SyntheticQa::DemoJobs.find(job.job_id)
    assert_equal "succeeded", summary[:state]
    assert_equal 34, summary.dig(:result, "usersRemoved")
    assert_equal %w[demo-20260926-1500 demo-20260926-1501], summary.dig(:result, "batches")

    assert_no_user_traces(user_ids)
    assert_equal 3, User.synthetic("qa-keep-me").count
    assert User.exists?(control.id)

    again = DemoDataPurgeJob.new(admin_id: @admin.id)
    again.perform_now
    assert_equal 0, SyntheticQa::DemoJobs.find(again.job_id).dig(:result, "usersRemoved")
  ensure
    SyntheticQa::BatchCleanup.call(batch: "qa-keep-me")
  end

  test "purge job refuses non-demo batches" do
    SyntheticQa::BatchSeeder.call(batch: "qa-keep-me", jobseekers: 1, employers: 1)
    job = DemoDataPurgeJob.new(admin_id: @admin.id, batches: ["qa-keep-me"])
    job.perform_now
    assert_equal "failed", SyntheticQa::DemoJobs.find(job.job_id)[:state]
    assert_equal 2, User.synthetic("qa-keep-me").count
  ensure
    SyntheticQa::BatchCleanup.call(batch: "qa-keep-me")
  end
end
