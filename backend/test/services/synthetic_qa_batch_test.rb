require "test_helper"

class SyntheticQaBatchTest < ActiveSupport::TestCase
  BATCH = "service-test-batch"

  teardown { SyntheticQa::BatchCleanup.call(batch: BATCH) }

  test "creates a representative reversible graph and removes every trace" do
    control = User.create!(name: "Control User", email: "control@example.com", password: "StrongPass123!", role: "jobseeker", status: "active")
    control.create_profile!

    result = SyntheticQa::BatchSeeder.call(batch: BATCH, jobseekers: 12, employers: 4)
    assert_equal 12, result.jobseekers
    assert_equal 4, result.employers
    assert_equal 16, User.synthetic(BATCH).count
    assert_equal 4, Job.where(employer_id: User.synthetic(BATCH).employer).count
    assert_equal 12, Application.joins(:candidate).where(users: { synthetic_batch: BATCH }).count
    assert_equal 12, Conversation.joins(:candidate).where(users: { synthetic_batch: BATCH }).count
    assert_equal 4, BookingRequest.joins(:requester).where(users: { synthetic_batch: BATCH }).count
    assert User.synthetic(BATCH).first.authenticate("SyntheticPass123!")

    user_ids = User.synthetic(BATCH).pluck(:id)
    entity_ids = synthetic_entity_ids(user_ids)
    cleanup = SyntheticQa::BatchCleanup.call(batch: BATCH)

    assert_equal 16, cleanup.users_removed
    assert_operator cleanup.records_removed, :>, 100
    assert_equal 0, User.synthetic(BATCH).count
    assert User.exists?(control.id), "cleanup must never remove an untagged account"
    assert_no_foreign_key_traces(user_ids)
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
