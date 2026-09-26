require "test_helper"

class UploadContractTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(name: "Upload QA", email: "upload-#{SecureRandom.hex(6)}@example.invalid",
      password: "StrongPass123!", role: "jobseeker", status: "active")
    @token = SecureRandom.urlsafe_base64(48)
    @user.sessions.create!(token_digest: Digest::SHA256.hexdigest(@token), expires_at: 1.day.from_now)
    @bucket = ENV.delete("AWS_BUCKET")
  end

  teardown { ENV["AWS_BUCKET"] = @bucket if @bucket }

  test "upload preparation requires authentication" do
    post "/api/uploads/presign", params: { filename: "sample.mp3", contentType: "audio/mpeg", size: 42 }, as: :json
    assert_response :unauthorized
  end

  test "upload preparation rejects unsupported MIME and excessive size before storage" do
    post "/api/uploads/presign", params: { filename: "script.html", contentType: "text/html", size: 42 }, headers: auth, as: :json
    assert_response :unprocessable_content

    post "/api/uploads/presign", params: { filename: "sample.mp3", contentType: "audio/mpeg", size: 100.megabytes + 1 }, headers: auth, as: :json
    assert_response :unprocessable_content
  end

  test "test environment advertises the authenticated local upload fallback" do
    post "/api/uploads/presign", params: { filename: "sample.mp3", contentType: "audio/mpeg", size: 42 }, headers: auth, as: :json
    assert_response :success
    assert_equal "proxied", response.parsed_body.fetch("mode")
    assert_equal "/api/uploads/local", response.parsed_body.fetch("uploadUrl")

    put "/api/uploads/local", params: "<script>unsafe</script>", headers: auth.merge("CONTENT_TYPE" => "text/html", "X-Filename" => "script.html")
    assert_response :unprocessable_content
  end

  private

  def auth = { "Authorization" => "Bearer #{@token}" }
end
