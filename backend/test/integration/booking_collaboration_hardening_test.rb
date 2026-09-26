require "test_helper"

# Regressions found by the booking/collaboration crawl: invalid input must answer 4xx with a
# readable message (never 500), and every booking transition names the party allowed to make it.
class BookingCollaborationHardeningTest < ActionDispatch::IntegrationTest
  setup do
    @artist = create_user("Hardening Artist", "jobseeker")
    @buyer = create_user("Hardening Buyer", "employer")
    @outsider = create_user("Hardening Outsider", "employer")
    @act = @artist.owned_acts.create!(name: "Hardening Band", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
  end

  test "booking enquiries validate required fields dates and budgets without server errors" do
    base = { actId: @act.id, eventType: "wedding", eventDate: 2.months.from_now.to_date.iso8601, city: "Pune" }

    post "/api/bookings", params: base.except(:city), headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity
    assert_match(/City can't be blank/, response.parsed_body.fetch("error"))
    post "/api/bookings", params: base.except(:eventType), headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity
    post "/api/bookings", params: base.merge(eventDate: "garbage"), headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity
    assert_equal "Choose a valid event date.", response.parsed_body.fetch("error")
    post "/api/bookings", params: base.merge(eventDate: "2020-01-01"), headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity
    post "/api/bookings", params: base.merge(budgetMin: 9_000, budgetMax: 10), headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity
    post "/api/bookings", params: base.merge(actId: "missing"), headers: auth(@buyer), as: :json
    assert_response :not_found
    assert_equal "This act is no longer available for booking.", response.parsed_body.fetch("error")
    post "/api/bookings", params: base, headers: auth(@buyer), as: :json
    assert_response :created
  end

  test "quotes reject oversized fees and bad currencies and supersede the previous quote" do
    booking = create_booking
    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 10_000_000_000 }, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 1_000, currency: "rupees" }, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    assert_match(/Currency must be a 3-letter code/, response.parsed_body.fetch("error"))
    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 0 }, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity

    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 1_000, currency: "inr" }, headers: auth(@artist), as: :json
    assert_response :created
    first = response.parsed_body.fetch("id")
    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 1_200 }, headers: auth(@buyer), as: :json
    assert_response :forbidden
    assert_equal "Only the act owner can send a quote.", response.parsed_body.fetch("error")
    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 1_000 }, headers: auth(@outsider), as: :json
    assert_response :not_found
    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 1_500 }, headers: auth(@artist), as: :json
    assert_response :created
    assert_equal "superseded", BookingQuote.find(first).status
    assert_equal "INR", BookingQuote.find(response.parsed_body.fetch("id")).currency
  end

  test "status changes explain the wrong party invalid states and a missing quote" do
    booking = create_booking

    post "/api/bookings/#{booking.id}/status", params: { status: "cancelled" }, headers: auth(@artist), as: :json
    assert_response :forbidden
    assert_equal "Only the person who sent the enquiry can mark this booking cancelled.", response.parsed_body.fetch("error")
    post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, headers: auth(@buyer), as: :json
    assert_response :conflict
    assert_equal "This booking is requested and cannot be marked accepted.", response.parsed_body.fetch("error")
    post "/api/bookings/#{booking.id}/status", params: { status: "bogus" }, headers: auth(@buyer), as: :json
    assert_response :bad_request
    post "/api/bookings/#{booking.id}/status", params: { status: "declined" }, headers: auth(@outsider), as: :json
    assert_response :not_found

    # requested -> negotiating -> accepted used to succeed with no quote and strand the deposit.
    post "/api/bookings/#{booking.id}/status", params: { status: "negotiating" }, headers: auth(@buyer), as: :json
    assert_response :success
    post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, headers: auth(@buyer), as: :json
    assert_response :conflict
    assert_match(/no quote to accept/, response.parsed_body.fetch("error"))

    post "/api/bookings/#{booking.id}/quote", params: { performanceFee: 1_000 }, headers: auth(@artist), as: :json
    assert_response :created
    post "/api/bookings/#{booking.id}/status", params: { status: "declined" }, headers: auth(@buyer), as: :json
    assert_response :forbidden
    assert_equal "Only the act owner can mark this booking declined.", response.parsed_body.fetch("error")

    get "/api/bookings", headers: auth(@buyer)
    row = response.parsed_body.fetch("bookings").find { _1.fetch("id") == booking.id }
    assert_equal %w[accepted negotiating cancelled], row.fetch("allowedTransitions")
    assert_equal false, row.fetch("depositPaid")

    post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, headers: auth(@buyer), as: :json
    assert_response :success
    assert_equal "accepted", booking.reload.status
    assert_equal "accepted", booking.booking_quotes.order(:created_at).last.status
    post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, headers: auth(@buyer), as: :json
    assert_response :conflict
    assert_equal "This booking is accepted and cannot be marked accepted.", response.parsed_body.fetch("error")

    post "/api/bookings/#{booking.id}/payment-order", params: {}, headers: auth(@buyer), as: :json
    assert_response :success
    post "/api/booking-payments/#{response.parsed_body.dig('payment', 'id')}/confirm", params: {}, headers: auth(@buyer), as: :json
    assert_response :success
    get "/api/bookings", headers: auth(@artist)
    row = response.parsed_body.fetch("bookings").find { _1.fetch("id") == booking.id }
    assert_equal true, row.fetch("depositPaid")
    assert_equal %w[completed disputed], row.fetch("allowedTransitions")
    post "/api/bookings/#{booking.id}/status", params: { status: "completed" }, headers: auth(@artist), as: :json
    assert_response :success
  end

  test "an expired quote cannot be accepted" do
    booking = create_booking
    quote = booking.booking_quotes.create!(created_by: @artist, performance_fee: 1_000, currency: "INR", status: "sent", valid_until: 1.day.from_now)
    booking.update!(status: "quoted")
    quote.update_column(:valid_until, 1.hour.ago)
    post "/api/bookings/#{booking.id}/status", params: { status: "accepted" }, headers: auth(@buyer), as: :json
    assert_response :conflict
    assert_match(/expired/, response.parsed_body.fetch("error"))
  end

  test "band projects workspaces and urgent responses reject blank or malformed input" do
    post "/api/band-projects", params: {}, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    assert_match(/Name can't be blank/, response.parsed_body.fetch("error"))
    post "/api/band-projects", params: { name: "Crew", genres: "rock" }, headers: auth(@artist), as: :json
    assert_response :created
    project_id = response.parsed_body.fetch("id")
    assert_equal ["rock"], BandProject.find(project_id).genres
    post "/api/band-projects/#{project_id}/roles", params: {}, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    post "/api/band-projects/#{project_id}/roles", params: { roleName: "Drummer", countNeeded: 0 }, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    post "/api/band-projects/#{project_id}/roles", params: { roleName: "Drummer" }, headers: auth(@artist), as: :json
    assert_response :created

    post "/api/organizations", params: {}, headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity
    post "/api/organizations", params: { name: "   " }, headers: auth(@buyer), as: :json
    assert_response :unprocessable_entity

    urgent = @buyer.urgent_requests.create!(title: "Need drummer", role_name: "Drummer", city: "Pune", currency: "INR", status: "open", start_at: 2.days.from_now)
    post "/api/urgent-requests/#{urgent.id}/respond", params: { rate: "abc" }, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    post "/api/urgent-requests/#{urgent.id}/respond", params: { message: "x" * 1_001 }, headers: auth(@artist), as: :json
    assert_response :unprocessable_entity
    post "/api/urgent-requests/#{urgent.id}/respond", params: { message: "Free that night", rate: "12000" }, headers: auth(@artist), as: :json
    assert_response :created
    assert_equal 12_000, UrgentRequestResponse.find_by(urgent_request_id: urgent.id, user_id: @artist.id).rate
  end

  test "array and hash filters answer 400 and another party's booking stays hidden" do
    get "/api/public/acts", params: { q: ["a"] }
    assert_response :bad_request
    assert_equal "INVALID_PARAMETER", response.parsed_body.fetch("code")
    get "/api/public/acts", params: { city: { x: "y" } }
    assert_response :bad_request
    get "/api/acts", params: { q: ["a"] }, headers: auth(@buyer)
    assert_response :bad_request
    get "/api/urgent-requests", params: { city: ["a"] }, headers: auth(@buyer)
    assert_response :bad_request
    post "/api/bookings", params: { actId: [@act.id], eventType: "wedding", city: "Pune", eventDate: 1.month.from_now.to_date.iso8601 }, headers: auth(@buyer), as: :json
    assert_response :bad_request

    booking = create_booking
    post "/api/bookings/#{booking.id}/status", params: { status: "cancelled" }, headers: auth(@outsider), as: :json
    assert_response :not_found
    get "/api/bookings/#{booking.id}/payments", headers: auth(@outsider)
    assert_response :not_found
  end

  test "urgent request listing does not query per row" do
    5.times { |i| @buyer.urgent_requests.create!(title: "Need #{i}", role_name: "Drummer", city: "Pune", currency: "INR", status: "open", start_at: 2.days.from_now) }
    headers = auth(@artist)
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:sql].start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get "/api/urgent-requests", headers: }
    assert_response :success
    assert_equal 5, response.parsed_body.fetch("requests").size
    assert_operator queries, :<=, 12
  end

  private

  def create_user(name, role)
    User.create!(name:, email: "#{name.parameterize}-#{SecureRandom.hex(3)}@example.com", password: "StrongPass123!", role:, status: "active").tap(&:create_profile!)
  end

  def create_booking
    BookingRequest.create!(act: @act, requester: @buyer, event_type: "concert", city: "Mumbai", currency: "INR", status: "requested", event_date: 1.month.from_now.to_date)
  end

  def auth(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    { "Authorization" => "Bearer #{raw}" }
  end
end
