require "test_helper"

class SearchSynonymsVisibilityTest < ActionDispatch::IntegrationTest
  test "synonym groups work in both directions" do
    singer = create_user("Asha Rao", "asha-search@example.com", "jobseeker")
    singer.create_profile!(headline: "Playback singer", location: "Mumbai", skills: ["Hindi"])
    keys = create_user("Kabir Mehta", "kabir-search@example.com", "jobseeker")
    keys.create_profile!(headline: "Keyboardist for tours", location: "Pune")

    get "/api/search", params: { q: "vocalist", type: "talent" }
    assert_includes titles, "Asha Rao", "vocalist must also search singer"
    assert_includes response.parsed_body["interpretedAs"], "playback singer"

    get "/api/search", params: { q: "pianist", type: "talent" }
    assert_includes titles, "Kabir Mehta", "pianist must also search keyboardist"

    get "/api/search", params: { q: "bassoon", type: "talent" }
    assert_equal ["bassoon"], response.parsed_body["interpretedAs"], "unrelated words gain no synonyms"
  end

  test "search hides non-demo synthetic jobs and acts from real visitors but shows demo ones" do
    hidden = create_user("QA Hidden Studio", "qa-hidden-search@example.invalid", "employer", synthetic_batch: "local-qa")
    demo = create_user("Demo Studio", "demo-search@example.invalid", "employer", synthetic_batch: "demo-20260926-1200")
    [hidden, demo].each do |owner|
      Job.create!(employer: owner, title: "Quasar session drummer #{owner.name}", company: owner.name, location: "Mumbai", kind: "Contract", genre: "Rock",
        description: "Record drums for a studio album with written terms and agreed compensation for every session.", status: "published")
      Act.create!(owner:, name: "Quasar Band #{owner.name}", act_type: "band", currency: "INR", fee_basis: "event", status: "active")
    end

    get "/api/search", params: { q: "Quasar" }
    assert_response :success
    assert titles.none? { _1.include?("QA Hidden Studio") }, "non-demo synthetic data must stay hidden: #{titles.inspect}"
    assert_includes titles, "Quasar session drummer Demo Studio"
    assert_includes titles, "Quasar Band Demo Studio"
    assert response.parsed_body["results"].select { _1["title"].include?("Demo Studio") }.all? { _1["demo"] }

    viewer = create_user("QA Viewer", "qa-viewer-search@example.invalid", "jobseeker", synthetic_batch: "local-qa")
    get "/api/search", params: { q: "Quasar" }, headers: { "Authorization" => "Bearer #{session_for(viewer)}" }
    assert_includes titles, "Quasar Band QA Hidden Studio", "synthetic viewers still see their own batch"
  end

  private

  def titles = response.parsed_body["results"].map { _1["title"] }

  def create_user(name, email, role, synthetic_batch: nil)
    User.create!(name:, email:, password: "StrongPass123!", role:, status: "active", profile_complete: true, synthetic_batch:)
  end

  def session_for(user)
    raw = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(raw), expires_at: 30.days.from_now)
    raw
  end
end
