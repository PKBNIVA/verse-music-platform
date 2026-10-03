require "test_helper"
require_relative "../support/realtime_test_people"

# Action Cable: ticket-based connection auth and per-channel authorisation.
class RealtimeConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection
  include RealtimeTestPeople

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @original_cache }

  def connect_with(ticket) = connect(headers: { "Sec-WebSocket-Protocol" => "actioncable-v1-json, #{RealtimeTicket::PROTOCOL_PREFIX}#{ticket}" })

  test "a fresh ticket in the subprotocol header connects as its session's user" do
    user, session = person_with_session("Ticket Holder")
    connect_with RealtimeTicket.issue(session)
    assert_equal user, connection.current_user
    assert_equal session, connection.current_session
  end

  test "a ticket works once" do
    _user, session = person_with_session("Once Only")
    ticket = RealtimeTicket.issue(session)
    connect_with ticket
    assert_reject_connection { connect_with ticket }
  end

  test "a ticket in the URL is not accepted (URLs are logged)" do
    _user, session = person_with_session("Url Ticket")
    assert_reject_connection { connect params: { ticket: RealtimeTicket.issue(session) } }
  end

  test "no ticket, a forged one, an expired one or an ended session are rejected" do
    user, session = person_with_session("Rejected")
    assert_reject_connection { connect }
    assert_reject_connection { connect_with "forged" }
    assert_reject_connection { connect_with ActiveSupport::MessageVerifier.new("other", url_safe: true).generate({ "s" => session.id, "j" => "x" }) }
    ticket = RealtimeTicket.issue(session)
    travel(RealtimeTicket.ttl + 1.second) { assert_reject_connection { connect_with ticket } }
    ticket = RealtimeTicket.issue(session)
    session.update!(expires_at: 1.minute.ago)
    assert_reject_connection { connect_with ticket }
    user.update!(status: "suspended")
    session.update!(expires_at: 1.day.from_now)
    assert_reject_connection { connect_with RealtimeTicket.issue(session) }
  end
end

class ConversationChannelTest < ActionCable::Channel::TestCase
  include RealtimeTestPeople

  test "participants subscribe; anyone else is rejected" do
    hirer, = person_with_session("Hirer", role: "employer")
    musician, = person_with_session("Musician")
    stranger, = person_with_session("Stranger")
    conversation = Conversation.create!(candidate: musician, employer: hirer)
    stub_connection current_user: musician
    subscribe id: conversation.id
    assert subscription.confirmed?
    assert_has_stream_for conversation

    stub_connection current_user: stranger
    subscribe id: conversation.id
    assert subscription.rejected?
    subscribe id: "missing"
    assert subscription.rejected?

    UserBlock.create!(blocker: hirer, blocked: musician)
    stub_connection current_user: musician
    subscribe id: conversation.id
    assert subscription.rejected?, "no live thread while either side has blocked the other"
  end
end

class UrgentRequestChannelTest < ActionCable::Channel::TestCase
  include RealtimeTestPeople

  test "only the hirer who posted the request subscribes" do
    hirer, = person_with_session("Urgent Hirer", role: "employer")
    musician, = person_with_session("Urgent Musician")
    request = UrgentRequest.create!(requester: hirer, title: "Drummer tonight", role_name: "Drummer", city: "Pune", start_at: 1.day.from_now, currency: "INR", status: "open")
    stub_connection current_user: hirer
    subscribe id: request.id
    assert_has_stream_for request
    stub_connection current_user: musician
    subscribe id: request.id
    assert subscription.rejected?
  end
end

class UserChannelTest < ActionCable::Channel::TestCase
  include RealtimeTestPeople

  test "streams the signed-in user's own updates" do
    user, = person_with_session("Badge Owner")
    stub_connection current_user: user
    subscribe
    assert_has_stream_for user
  end
end
