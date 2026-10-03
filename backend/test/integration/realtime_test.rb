require "test_helper"
require_relative "../support/realtime_test_people"
require "minitest/mock"

# POST /api/cable/ticket and the broadcasts that follow writes (Realtime).
class RealtimeTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper
  include RealtimeTestPeople

  setup do
    @hirer, @hirer_session = person_with_session("Live Hirer", role: "employer")
    @musician, @musician_session = person_with_session("Live Musician")
    @conversation = Conversation.create!(candidate: @musician, employer: @hirer)
  end

  test "a signed-in user gets a ticket for the socket; strangers do not; it is rate-limited" do
    post "/api/cable/ticket"
    assert_response :unauthorized

    post "/api/cable/ticket", headers: auth(@musician)
    assert_response :created
    body = response.parsed_body
    assert_equal RealtimeTicket.ttl.to_i, body["expiresIn"]
    assert_equal "ws://www.example.com/cable", body["url"]
    assert_equal @musician, RealtimeTicket.user_for(body["ticket"])
    assert_not_includes body["ticket"], @musician.id, "the ticket is signed, not a readable user id"

    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    freeze_time
    headers = auth(@hirer)
    RealtimeTicket.tickets_per_minute.times { post "/api/cable/ticket", headers: }
    assert_response :created
    post "/api/cable/ticket", headers: headers
    assert_response :too_many_requests
  ensure
    Rails.cache = original if original
  end

  test "sign-in and GET /me say whether live updates are on; off, no ticket is issued" do
    get "/api/me", headers: auth(@musician)
    assert_equal true, response.parsed_body["realtime"]
    RealtimeTicket.stub(:settings, RealtimeTicket.settings.merge("enabled" => false)) do
      get "/api/me", headers: auth(@musician)
      assert_equal false, response.parsed_body["realtime"]
      post "/api/cable/ticket", headers: auth(@musician)
      assert_response :service_unavailable
      assert_equal "REALTIME_DISABLED", response.parsed_body["code"]
    end
    @musician.update!(email_verified: true)
    post "/api/auth/login", params: { email: @musician.email, password: "StrongPass123!" }, as: :json
    assert_response :success
    assert_equal true, response.parsed_body["realtime"]
  end

  test "CABLE_ENABLED overrides the config without a deploy: off means 503 and realtime false" do
    previous = ENV["CABLE_ENABLED"]
    ENV["CABLE_ENABLED"] = "false"
    post "/api/cable/ticket", headers: auth(@musician)
    assert_response :service_unavailable
    get "/api/me", headers: auth(@musician)
    assert_equal false, response.parsed_body["realtime"], "the app then only polls"
    ENV["CABLE_ENABLED"] = "true"
    RealtimeTicket.stub(:settings, RealtimeTicket.settings.merge("enabled" => false)) do
      post "/api/cable/ticket", headers: auth(@musician)
      assert_response :created
    end
  ensure
    ENV["CABLE_ENABLED"] = previous
  end

  test "the ticket never reaches the logs" do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter("ticket" => "secret")
    assert_equal "[FILTERED]", filtered["ticket"]
  end

  test "signing out, revoking sessions and suspending close that session's open sockets" do
    raw = SecureRandom.urlsafe_base64(48)
    session = @musician.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 1.day.from_now)
    # Action Cable's internal channel for one connection (its identifiers' global ids, sorted).
    channel = ->(s) { "action_cable/#{[@musician, s].map(&:to_gid_param).sort.join(':')}" }
    disconnects = ->(s) { ActionCable.server.pubsub.broadcasts(channel.(s)).map { JSON.parse(_1) } }

    post "/api/auth/logout", headers: { "Authorization" => "Bearer #{raw}" }
    assert_equal [{ "type" => "disconnect", "reconnect" => false }], disconnects.(session)

    other = @musician.sessions.create!(token_digest: Digest::SHA256.hexdigest("other"), expires_at: 1.day.from_now)
    assert_equal 1, Session.revoke!(@musician.sessions.where(id: other.id))
    assert_equal 1, disconnects.(other).size

    third = @musician.sessions.create!(token_digest: Digest::SHA256.hexdigest("third"), expires_at: 1.day.from_now)
    admin, = person_with_session("Admin Mod", role: "admin")
    patch "/api/admin/users/#{@musician.id}", params: { status: "suspended" }, headers: auth(admin), as: :json
    assert_response :success
    assert_equal 1, disconnects.(third).size, "suspending an account closes its sockets"
  end

  test "a new message reaches the thread and the recipient's badge, with ids only" do
    post "/api/conversations/#{@conversation.id}/messages", params: { body: "Soundcheck at 6?" }, headers: auth(@hirer), as: :json
    assert_response :success
    message = Message.order(:created_at).last
    assert_broadcast_on(ConversationChannel.broadcasting_for(@conversation), { type: "message", id: message.id, conversationId: @conversation.id })
    assert_broadcast_on(UserChannel.broadcasting_for(@musician), { type: "message", conversationId: @conversation.id })
    assert_no_broadcasts(UserChannel.broadcasting_for(@hirer))
  end

  test "a new notification reaches its user" do
    notification = Notification.create!(user: @musician, kind: "system", title: "Welcome")
    assert_broadcast_on(UserChannel.broadcasting_for(@musician), { type: "notification", id: notification.id })
  end

  test "an urgent request's status, matching and responses reach the hirer's page" do
    request = UrgentRequest.create!(requester: @hirer, title: "Drummer tonight", role_name: "Drummer", city: "Pune", start_at: 1.day.from_now, currency: "INR", status: "open")
    stream = UrgentRequestChannel.broadcasting_for(request)
    assert_no_broadcasts(stream)

    UrgentMatchJob.perform_now(request.id)
    assert_broadcast_on(stream, { type: "status", id: request.id, status: "open", matchStatus: "done" })

    post "/api/urgent-requests/#{request.id}/respond", params: { message: "Free tonight" }, headers: auth(@musician), as: :json
    assert_response :success
    assert_broadcast_on(stream, { type: "response", id: request.id, status: "open", matchStatus: "done" })

    request.reload.update!(status: "closed")
    assert_broadcast_on(stream, { type: "status", id: request.id, status: "closed", matchStatus: "done" })
  end

  test "a failed broadcast never fails the write" do
    UserChannel.stub(:broadcast_to, ->(*) { raise "adapter down" }) do
      assert_difference("Notification.count") { Notification.create!(user: @musician, kind: "system", title: "Still saved") }
    end
  end

  private

  def auth(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    { "Authorization" => "Bearer #{raw}" }
  end
end
