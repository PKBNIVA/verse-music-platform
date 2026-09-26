require "test_helper"

class RequestSizeLimitTest < ActionDispatch::IntegrationTest
  test "JSON bodies over 1 MB are rejected with 413 before reaching a controller" do
    post "/api/auth/login", params: { email: "someone@example.com", password: "x" * (1.megabyte + 10) }, as: :json
    assert_response :payload_too_large
    assert_equal "PAYLOAD_TOO_LARGE", response.parsed_body["code"]
    assert_equal "application/json", response.media_type
  end

  test "ordinary requests under the limit are unaffected" do
    post "/api/auth/login", params: { email: "nobody@example.com", password: "WrongPass123!" }, as: :json
    assert_response :unauthorized
  end

  test "the streamed upload endpoint keeps its own larger limit" do
    put "/api/uploads/local", params: "x" * (2.megabytes), headers: { "Content-Type" => "audio/mpeg", "X-Filename" => "a.mp3" }
    assert_not_equal 413, response.status, "uploads must not be cut off at the JSON body limit"
  end

  test "chunked bodies without Content-Length are measured" do
    app = RequestSizeLimit.new(->(_env) { [200, {}, ["ok"]] }, limit: 10)
    small = Rack::MockRequest.env_for("/api/x", method: "POST", input: "12345", "HTTP_TRANSFER_ENCODING" => "chunked")
    small.delete("CONTENT_LENGTH")
    assert_equal 200, app.call(small).first
    assert_equal "12345", small["rack.input"].read, "the body is rewound for the app"

    big = Rack::MockRequest.env_for("/api/x", method: "POST", input: "x" * 50, "HTTP_TRANSFER_ENCODING" => "chunked")
    big.delete("CONTENT_LENGTH")
    assert_equal 413, app.call(big).first
  end
end
