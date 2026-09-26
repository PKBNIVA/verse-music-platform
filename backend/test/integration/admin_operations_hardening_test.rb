require "test_helper"

class AdminOperationsHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("Ops Admin", "ops-admin-hardening@example.com", "admin")
    @studio = create_user("Ops Studio", "ops-studio-hardening@example.com", "employer")
    @token = session_for(@admin)
  end

  test "reconciling a billing attempt without Razorpay keys answers 503 instead of crashing" do
    attempt = BillingAttempt.create!(user: @studio, operation: "subscription_create", provider: "razorpay",
                                     idempotency_key: SecureRandom.uuid, state: "ambiguous", provider_resource_id: "sub_hardening")
    with_env("RAZORPAY_KEY_ID" => nil, "RAZORPAY_KEY_SECRET" => nil) do
      post "/api/admin/billing-attempts/#{attempt.id}/reconcile", headers: auth(@token)
    end
    assert_response :service_unavailable
    assert_equal "PAYMENTS_NOT_CONFIGURED", response.parsed_body.fetch("code")
    assert_equal "ambiguous", attempt.reload.state
  end

  test "grant-plan rejects malformed durations and admin targets" do
    post "/api/admin/users/#{@studio.id}/grant-plan", params: { planCode: "pro", days: "abc" }, headers: auth(@token), as: :json
    assert_response :bad_request
    post "/api/admin/users/#{@studio.id}/grant-plan", params: { planCode: "pro", days: ["30"] }, headers: auth(@token), as: :json
    assert_response :bad_request
    post "/api/admin/users/#{@admin.id}/grant-plan", params: { planCode: "pro" }, headers: auth(@token), as: :json
    assert_response :unprocessable_content
    assert_equal 0, Subscription.where(user: [@studio, @admin]).count

    post "/api/admin/users/#{@studio.id}/grant-plan", params: { planCode: "studio", days: 45 }, headers: auth(@token), as: :json
    assert_response :created
    subscription = Subscription.find(response.parsed_body.fetch("id"))
    assert_equal "studio", subscription.plan_code
    assert_in_delta 45.days.from_now, subscription.current_period_end, 5.seconds
  end

  test "rejecting a previously approved verification removes the badge and is audited" do
    request_record = VerificationRequest.create!(user: @studio, kind: "organization", evidence_url: "https://example.com/studio", status: "pending")
    patch "/api/admin/verifications/#{request_record.id}", params: { status: "approved" }, headers: auth(@token), as: :json
    assert_response :success
    assert @studio.profile.reload.verified?

    patch "/api/admin/verifications/#{request_record.id}", params: { status: "rejected" }, headers: auth(@token), as: :json
    assert_response :success
    assert_not @studio.profile.reload.verified?
    assert_equal 2, AuditLog.where(action: "admin.verification.status", entity_id: request_record.id).count
  end

  test "approving an opportunity keeps the automated moderation hints; rejecting records the reason" do
    job = Job.create!(employer: @studio, title: "Session Bassist", company: "Ops Studio", location: "Mumbai", kind: "Contract",
                      genre: "Studio", description: "A paid studio session with agreed terms, charts and a reference track.",
                      status: "pending", moderation_note: "Low compensation detail")
    patch "/api/admin/jobs/#{job.id}", params: { status: "rejected", note: "Please add the fee range." }, headers: auth(@token), as: :json
    assert_response :success
    assert_equal "Please add the fee range.", job.reload.moderation_note

    patch "/api/admin/jobs/#{job.id}", params: { status: "published" }, headers: auth(@token), as: :json
    assert_response :success
    assert_equal "published", job.reload.status
    assert_equal "Please add the fee range.", job.moderation_note
  end

  private

  def with_env(values)
    previous = values.keys.index_with { ENV[_1] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def create_user(name, email, role)
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active").tap(&:create_profile!)
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
