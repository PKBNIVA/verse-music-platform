require "test_helper"

class AdminSignInDoctorTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("Doctor Admin", "doctor-admin@example.com", "admin")
    @artist = create_user("Doctor Artist", "doctor-artist@example.com", "jobseeker")
    @token = session_for(@admin)
  end

  test "only admins can use the sign-in doctor" do
    get "/api/admin/users/lookup", params: { email: @artist.email }
    assert_response :unauthorized
    get "/api/admin/users/lookup", params: { email: @artist.email }, headers: auth(session_for(@artist))
    assert_response :forbidden
    post "/api/admin/users/#{@artist.id}/revoke-sessions", headers: auth(session_for(@artist))
    assert_response :forbidden
  end

  test "lookup explains a suspended, unverified account without leaking secrets" do
    @artist.update!(status: "suspended", email_verified: false)
    @artist.sessions.create!(token_digest: Digest::SHA256.hexdigest("stale"), expires_at: 1.day.ago)
    @artist.email_tokens.create!(purpose: "reset_password", token_digest: Digest::SHA256.hexdigest("reset-secret"), expires_at: 1.hour.from_now)
    AuditLog.create!(actor: @artist, action: "auth.login", entity_type: "User", entity_id: @artist.id, metadata: { ip: "203.0.113.77" })

    get "/api/admin/users/lookup", params: { email: "  Doctor-Artist@Example.com " }, headers: auth(@token)
    assert_response :success
    body = response.parsed_body
    assert_equal "doctor-artist@example.com", body["email"]
    assert body["exists"]
    assert_equal "suspended", body.dig("user", "status")
    assert_equal true, body.dig("user", "passwordSet")
    assert_equal 0, body.dig("sessions", "active")
    assert_equal 1, body.dig("sessions", "createdLast7Days")
    codes = body["diagnosis"].pluck("code")
    assert_includes codes, "ACCOUNT_SUSPENDED"
    assert_includes codes, "EMAIL_NOT_VERIFIED"
    assert_includes codes, "NEVER_SIGNED_IN"
    assert_equal [{ "action" => "auth.login", "ip" => "203.0.x.x" }], body["recentAuthEvents"].map { _1.except("at") }
    assert_equal "reset_password", body.dig("emailTokens", 0, "purpose")
    assert_includes [true, false], body["emailProviderConfigured"]

    raw = response.body
    %w[password_digest token_digest reset-secret 203.0.113.77].each { assert_not_includes raw, _1 }
    assert_not_includes raw, Digest::SHA256.hexdigest("reset-secret")
    assert AuditLog.exists?(actor: @admin, action: "admin.user.lookup", entity_id: @artist.id)
  end

  test "lookup of an unknown email and invalid input" do
    get "/api/admin/users/lookup", params: { email: "nobody@example.com" }, headers: auth(@token)
    assert_response :success
    assert_equal false, response.parsed_body["exists"]
    assert_equal ["NO_ACCOUNT"], response.parsed_body["diagnosis"].pluck("code")

    get "/api/admin/users/lookup", headers: auth(@token)
    assert_response :bad_request
    get "/api/admin/users/lookup?email[]=a", headers: auth(@token)
    assert_response :bad_request
  end

  test "healthy account reports no blockers and session cap is flagged" do
    @artist.update!(email_verified: true, last_login_at: 1.hour.ago)
    with_email_provider do
      get "/api/admin/users/lookup", params: { email: @artist.email }, headers: auth(@token)
    end
    assert_equal ["NO_BLOCKERS"], response.parsed_body["diagnosis"].pluck("code")

    AuthController::MAX_LIVE_SESSIONS.times { session_for(@artist) }
    with_email_provider do
      get "/api/admin/users/lookup", params: { email: @artist.email }, headers: auth(@token)
    end
    assert_includes response.parsed_body["diagnosis"].pluck("code"), "SESSION_CAP"
  end

  test "revoke-sessions signs the user out everywhere and is audited" do
    user_token = session_for(@artist)
    session_for(@artist)
    post "/api/admin/users/#{@artist.id}/revoke-sessions", headers: auth(@token)
    assert_response :success
    assert_equal 2, response.parsed_body["revoked"]
    assert_equal 0, @artist.sessions.count
    assert AuditLog.exists?(actor: @admin, action: "admin.user.revoke_sessions", entity_id: @artist.id)
    get "/api/me", headers: auth(user_token)
    assert_response :unauthorized

    post "/api/admin/users/#{@admin.id}/revoke-sessions", headers: auth(@token)
    assert_response :conflict
    post "/api/admin/users/missing/revoke-sessions", headers: auth(@token)
    assert_response :not_found
  end

  private

  def with_email_provider
    previous = ENV["EMAIL_DELIVERY_WEBHOOK"]
    ENV["EMAIL_DELIVERY_WEBHOOK"] = "https://example.com/email-hook"
    yield
  ensure
    ENV["EMAIL_DELIVERY_WEBHOOK"] = previous
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
