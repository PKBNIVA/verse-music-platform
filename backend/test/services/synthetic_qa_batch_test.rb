require "test_helper"
require_relative "../synthetic_trace_assertions"

class SyntheticQaBatchTest < ActiveSupport::TestCase
  include SyntheticTraceAssertions
  BATCH = "service-test-batch"

  teardown { SyntheticQa::BatchCleanup.call(batch: BATCH) }

  test "creates a representative reversible graph and removes every trace" do
    control = User.create!(name: "Control User", email: "control@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    control.create_profile!

    result = SyntheticQa::BatchSeeder.call(batch: BATCH, jobseekers: 12, employers: 4)
    assert_equal 12, result.jobseekers
    assert_equal 4, result.employers
    assert_equal 16, User.synthetic(BATCH).count
    assert_equal 8, Job.where(employer_id: User.synthetic(BATCH).employer).count
    assert_equal 12, Application.joins(:candidate).where(users: { synthetic_batch: BATCH }).count
    assert_equal 12, Conversation.joins(:candidate).where(users: { synthetic_batch: BATCH }).count
    assert_equal 8, BookingRequest.joins(:requester).where(users: { synthetic_batch: BATCH }).count
    assert User.synthetic(BATCH).first.authenticate("SyntheticPass123!")

    user_ids = User.synthetic(BATCH).pluck(:id)
    entity_ids = synthetic_entity_ids(user_ids)
    cleanup = SyntheticQa::BatchCleanup.call(batch: BATCH)

    assert_equal 16, cleanup.users_removed
    assert_operator cleanup.records_removed, :>, 100
    assert_equal 0, User.synthetic(BATCH).count
    assert User.exists?(control.id), "cleanup must never remove an untagged account"
    assert_no_foreign_key_traces(user_ids)
    assert_no_user_traces(user_ids)
    assert_equal 0, Report.where(entity_id: entity_ids).count
    assert_equal 0, AuditLog.where(entity_id: entity_ids).count

    repeated = SyntheticQa::BatchCleanup.call(batch: BATCH)
    assert_equal 0, repeated.users_removed
  ensure
    control&.destroy!
  end

  test "refuses duplicate batches instead of mixing runs" do
    SyntheticQa::BatchSeeder.call(batch: BATCH, jobseekers: 2, employers: 1)
    error = assert_raises(ArgumentError) { SyntheticQa::BatchSeeder.call(batch: BATCH, jobseekers: 2, employers: 1) }
    assert_match(/purge it before reseeding/, error.message)
  end

  test "seeds every state each screen needs" do
    SyntheticQa::BatchSeeder.call(batch: BATCH, jobseekers: 20, employers: 8)
    users = User.synthetic(BATCH)
    assert_equal Application::STATUS_TRANSITIONS.keys.sort, Application.where(candidate_id: users.select(:id)).distinct.pluck(:status).sort
    assert_equal BookingRequest::STATUSES.sort, BookingRequest.where(requester_id: users.select(:id)).distinct.pluck(:status).sort
    assert_equal %w[audition collaboration gig internship job session tour], Job.where(employer_id: users.select(:id)).distinct.pluck(:opportunity_kind).sort
    assert_operator Job.where(employer_id: users.select(:id)).distinct.count(:location), :>=, 5
    assert_equal %w[pending published rejected], Review.where(employer_id: users.select(:id)).distinct.pluck(:status).sort
    assert ActMember.joins(:act).where(acts: { owner_id: users.select(:id) }).group(:act_id).count.values.max >= 2, "bands have members"
    assert BookingQuote.where(created_by_id: users.select(:id)).exists?
    assert BookingPayment.where(payer_id: users.select(:id), status: "paid").exists?
    assert BandProject.where(owner_id: users.select(:id)).exists?
    assert UrgentRequest.where(requester_id: users.select(:id)).exists?
    assert Message.where(sender_id: users.select(:id)).count >= 40
    assert PortfolioItem.where(user_id: users.select(:id), kind: "video").where("url LIKE 'https://www.youtube.com/%'").exists?
    assert Profile.where(user_id: users.select(:id)).where.not(headline: nil).count == 28
    assert_operator AvailabilityWindow.where(user_id: users.select(:id)).distinct.count(:status), :>=, 4
    assert_operator Notification.where(user_id: users.select(:id)).distinct.count(:kind), :>=, 6
  end

  test "demo batches get a random password, realistic names and stay on example.invalid" do
    batch = "demo-20260926-0000"
    SyntheticQa::BatchSeeder.call(batch:, jobseekers: 3, employers: 2)
    users = User.synthetic(batch).to_a
    assert users.all? { _1.email.end_with?("@example.invalid") }
    assert users.none? { _1.authenticate("SyntheticPass123!") }, "demo accounts must not accept the QA password"
    assert users.none? { _1.name.start_with?("QA ") }
    assert users.map(&:password_digest).uniq.one?, "one random password per batch"
  ensure
    SyntheticQa::BatchCleanup.call(batch:)
  end

  test "admin-authorized seeding is limited to demo batches and the user cap" do
    admin = User.create!(name: "Admin", email: "cap-admin@example.com", password: "StrongPass123!", role: "admin", status: "active")
    error = assert_raises(ArgumentError) { SyntheticQa::BatchSeeder.call(batch: "qa-not-demo", jobseekers: 1, employers: 1, authorized_by: admin) }
    assert_match(/demo-\*/, error.message)
    error = assert_raises(ArgumentError) { SyntheticQa::BatchSeeder.call(batch: "demo-too-big", jobseekers: 250, employers: 51, authorized_by: admin) }
    assert_match(/capped at 300/, error.message)
    jobseeker = User.create!(name: "Not Admin", email: "cap-js@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    assert_raises(SecurityError) { SyntheticQa::BatchSeeder.call(batch: "demo-by-jobseeker", jobseekers: 1, employers: 1, authorized_by: jobseeker) }
    assert_raises(ArgumentError) { SyntheticQa::BatchCleanup.call(batch: BATCH, authorized_by: admin) }
    assert_equal 0, User.where("synthetic_batch LIKE 'demo-%'").count
  end

  private

  def synthetic_entity_ids(user_ids)
    job_ids = Job.where(employer_id: user_ids).pluck(:id)
    application_ids = Application.where(job_id: job_ids).or(Application.where(candidate_id: user_ids)).pluck(:id)
    act_ids = Act.where(owner_id: user_ids).pluck(:id)
    booking_ids = BookingRequest.where(act_id: act_ids).or(BookingRequest.where(requester_id: user_ids)).pluck(:id)
    user_ids + job_ids + application_ids + act_ids + booking_ids
  end

  def assert_no_foreign_key_traces(user_ids)
    checks = {
      Profile => %i[user_id], Session => %i[user_id], Job => %i[employer_id], Application => %i[candidate_id],
      SavedJob => %i[user_id], JobAlert => %i[user_id], PortfolioItem => %i[user_id], Notification => %i[user_id],
      Report => %i[reporter_id resolved_by_id], Review => %i[author_id employer_id], VerificationRequest => %i[user_id reviewed_by_id],
      EmailToken => %i[user_id], AuditLog => %i[actor_id], Subscription => %i[user_id], AvailabilityWindow => %i[user_id],
      RecentActivity => %i[user_id], TalentShortlist => %i[employer_id candidate_id], Conversation => %i[candidate_id employer_id],
      Message => %i[sender_id], ApplicationEvent => %i[actor_id], Act => %i[owner_id], ActMember => %i[user_id],
      BookingRequest => %i[requester_id], BookingQuote => %i[created_by_id], BookingPayment => %i[payer_id],
      Organization => %i[owner_id], OrganizationMember => %i[user_id], UrgentRequest => %i[requester_id],
      UrgentRequestResponse => %i[user_id], TalentFolder => %i[owner_id], TalentFolderMember => %i[candidate_id],
      BandProject => %i[owner_id], CrewPlan => %i[owner_id], BillingEvent => %i[user_id], BillingAttempt => %i[user_id]
    }
    checks.each do |model, columns|
      columns.each do |column|
        assert_equal 0, model.where(column => user_ids).count, "#{model.table_name}.#{column} retained synthetic references"
      end
    end
  end
end
