require "test_helper"
require "minitest/mock"
require "aws-sdk-s3"

# Direct (S3/R2) and streamed (Disk) upload lifecycle against an in-memory fake bucket.
# No network: the AWS client runs with stub_responses.
class UploadStorageTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PNG = "\x89PNG\r\n\x1A\n".b + ("\x00".b * 64)
  MP3 = "ID3\x04\x00\x00\x00\x00\x00\x00".b + ("\x00".b * 64)
  PDF = "%PDF-1.7\n".b + ("x" * 64)
  STORAGE_ENV = %w[AWS_BUCKET AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_ENDPOINT_URL_S3 AWS_PUBLIC_BASE_URL AWS_UPLOAD_METHOD API_HOST].freeze

  setup do
    @saved_env = STORAGE_ENV.to_h { [_1, ENV.delete(_1)] }
    @objects = {}
    @user, @token = create_user("artist")
    @other, @other_token = create_user("other")
  end

  teardown do
    STORAGE_ENV.each { |name| @saved_env[name].nil? ? ENV.delete(name) : ENV[name] = @saved_env[name] }
  end

  test "direct mode issues a POST policy that pins size, type and key and records a pending upload" do
    with_bucket do
      post "/api/uploads/presign", params: { filename: "My Song!.mp3", contentType: "audio/mpeg", size: MP3.bytesize }, headers: auth, as: :json
      assert_response :success
      body = response.parsed_body
      assert_equal %w[direct POST], body.values_at("mode", "method")
      upload = Upload.find(body.fetch("id"))
      assert_equal ["pending", @user.id, "audio/mpeg", MP3.bytesize], [upload.status, upload.user_id, upload.content_type, upload.byte_size]
      assert_match %r{\Auploads/#{@user.id}/[0-9a-f-]{36}/My_Song_.mp3\z}, upload.key
      assert_equal "https://verse-test.s3.ap-south-1.amazonaws.com/#{upload.key}", body.fetch("publicUrl")

      policy = JSON.parse(Base64.decode64(body.dig("fields", "policy")))
      conditions = policy.fetch("conditions")
      assert_includes conditions, ["content-length-range", MP3.bytesize, MP3.bytesize]
      assert_includes conditions, { "Content-Type" => "audio/mpeg" }
      assert_includes conditions, { "key" => upload.key }
      assert_equal "audio/mpeg", body.dig("fields", "Content-Type")
    end
  end

  test "R2 endpoints require a public base URL and default to a signed PUT" do
    with_bucket(endpoint: "https://acct.r2.cloudflarestorage.com", public_base: nil) do
      post "/api/uploads/presign", params: { filename: "a.png", contentType: "image/png", size: 10 }, headers: auth, as: :json
      assert_response :service_unavailable
      assert_equal "STORAGE_MISCONFIGURED", response.parsed_body["code"]
      assert_equal ["missing_public_base_url"], UploadStorage.configuration_problems
      assert_equal 0, Upload.count
    end

    with_bucket(endpoint: "https://acct.r2.cloudflarestorage.com", public_base: "https://media.example.test/") do
      post "/api/uploads/presign", params: { filename: "a.png", contentType: "image/png", size: 10 }, headers: auth, as: :json
      assert_response :success
      body = response.parsed_body
      assert_equal "PUT", body["method"]
      assert_match(/X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost/, body["uploadUrl"])
      assert body["uploadUrl"].start_with?("https://acct.r2.cloudflarestorage.com/verse-test/uploads/")
      assert_equal "https://media.example.test/#{Upload.last.key}", body["publicUrl"]
    end
  end

  test "completion verifies stored size and magic bytes, deleting mismatched objects" do
    with_bucket do
      too_big = presign("song.mp3", "audio/mpeg", MP3.bytesize)
      @objects[too_big.key] = { body: MP3 + "extra", type: "audio/mpeg" }
      post "/api/uploads/#{too_big.id}/complete", headers: auth
      assert_response :unprocessable_content
      assert_match(/size/, response.parsed_body["error"])
      assert_not @objects.key?(too_big.key)
      assert_not Upload.exists?(too_big.id)

      disguised = presign("song.mp3", "audio/mpeg", 31)
      @objects[disguised.key] = { body: "<html><script>x</script></html>", type: "audio/mpeg" }
      post "/api/uploads/#{disguised.id}/complete", headers: auth
      assert_response :unprocessable_content
      assert_match(/contents/, response.parsed_body["error"])
      assert_not @objects.key?(disguised.key)

      missing = presign("song.mp3", "audio/mpeg", MP3.bytesize)
      post "/api/uploads/#{missing.id}/complete", headers: auth
      assert_response :conflict
      assert Upload.exists?(missing.id)

      good = presign("song.mp3", "audio/mpeg", MP3.bytesize)
      @objects[good.key] = { body: MP3, type: "audio/mpeg" }
      post "/api/uploads/#{good.id}/complete", headers: other_auth
      assert_response :not_found
      post "/api/uploads/#{good.id}/complete", headers: auth
      assert_response :success
      assert_equal good.public_url, response.parsed_body["url"]
      assert good.reload.complete?
    end
  end

  test "work samples accept external HTTPS links and only the owner's completed uploads" do
    with_bucket do
      pending = presign("demo.mp3", "audio/mpeg", MP3.bytesize)
      assert_rejected_sample(pending.public_url, /own completed uploads/)

      @objects[pending.key] = { body: MP3, type: "audio/mpeg" }
      post "/api/uploads/#{pending.id}/complete", headers: auth
      assert_response :success

      post "/api/portfolio", params: { type: "audio", title: "Stolen", url: pending.public_url }, headers: other_auth, as: :json
      assert_response :unprocessable_content

      assert_rejected_sample("https://verse-test.s3.ap-south-1.amazonaws.com/uploads/someone/else.mp3", /own completed uploads/)
      assert_rejected_sample("http://example.com/track", /HTTPS/)

      %w[https://youtu.be/dQw4w9WgXcQ https://open.spotify.com/track/abc https://soundcloud.com/a/b].each do |url|
        post "/api/portfolio", params: { type: "audio", title: "Embed", url: }, headers: auth, as: :json
        assert_response :created, response.body
      end
      post "/api/portfolio", params: { type: "audio", title: "Mine", url: pending.public_url }, headers: auth, as: :json
      assert_response :created
    end
  end

  test "deleting a work sample deletes its uploaded object unless another sample uses it" do
    with_bucket do
      upload = completed_direct_upload
      first = create_sample(upload.public_url)
      second = create_sample(upload.public_url)

      perform_enqueued_jobs { delete "/api/portfolio/#{first}", headers: auth }
      assert_response :success
      assert @objects.key?(upload.key), "object still used by another sample"

      delete "/api/uploads/#{upload.id}", headers: auth
      assert_response :conflict

      perform_enqueued_jobs { delete "/api/portfolio/#{second}", headers: auth }
      assert_not @objects.key?(upload.key)
      assert_not Upload.exists?(upload.id)
    end
  end

  test "daily sweep removes stale, unused and ownerless uploads and orphaned bucket objects" do
    with_bucket do
      stale_pending = presign("a.mp3", "audio/mpeg", 10)
      @objects[stale_pending.key] = { body: MP3, type: "audio/mpeg", at: 2.days.ago }
      fresh_pending = presign("b.mp3", "audio/mpeg", 10)
      unused = completed_direct_upload
      used = completed_direct_upload
      create_sample(used.public_url)
      ownerless = completed_direct_upload
      Upload.where(id: [stale_pending, unused, used, ownerless].map(&:id)).update_all(created_at: 2.days.ago)
      ownerless.update_columns(user_id: nil, created_at: Time.current)
      @objects["uploads/legacy/orphan.mp3"] = { body: MP3, type: "audio/mpeg", at: 3.days.ago }
      @objects["uploads/legacy/linked.mp3"] = { body: MP3, type: "audio/mpeg", at: 3.days.ago }
      @objects["uploads/legacy/recent.mp3"] = { body: MP3, type: "audio/mpeg", at: 1.hour.ago }
      legacy = @user.portfolio_items.new(kind: "audio", title: "Legacy", url: "https://verse-test.s3.ap-south-1.amazonaws.com/uploads/legacy/linked.mp3")
      legacy.save!(validate: false)

      counts = UploadSweepJob.perform_now

      assert_equal({ pending: 1, ownerDeleted: 1, unreferenced: 1, orphanObjects: 1 }, counts.symbolize_keys.slice(:pending, :ownerDeleted, :unreferenced, :orphanObjects))
      assert_equal [fresh_pending.id, used.id].sort, Upload.pluck(:id).sort
      assert_equal [used.key, "uploads/legacy/linked.mp3", "uploads/legacy/recent.mp3"].sort, @objects.keys.sort
    end
  end

  test "readiness reports storage misconfiguration as codes without secret values" do
    with_bucket(endpoint: "https://acct.r2.cloudflarestorage.com", public_base: nil) do
      ENV.delete("AWS_SECRET_ACCESS_KEY")
      storage = ReadinessChecks.new.call.fetch(:storage)
      assert_equal false, storage[:ok]
      assert_equal %w[missing_credentials missing_public_base_url], storage[:problems]
      refute_match(/acct|verse-test|test-access/, storage.to_json)
    end
  end

  test "streamed uploads go to disk only when the magic bytes match the declared type" do
    { "image/png" => PNG, "audio/mpeg" => MP3, "application/pdf" => PDF }.each do |type, bytes|
      put "/api/uploads/local", params: bytes, headers: auth.merge("CONTENT_TYPE" => type, "X-Filename" => "file")
      assert_response :created, response.body
      upload = Upload.find(response.parsed_body["id"])
      assert_equal ["disk", "complete", type, bytes.bytesize], [upload.storage, upload.status, upload.content_type, upload.byte_size]
      assert_equal bytes, ActiveStorage::Blob.find_by!(key: upload.key).download
    end

    put "/api/uploads/local", params: "<svg onload=alert(1)>", headers: auth.merge("CONTENT_TYPE" => "image/png", "X-Filename" => "x.png")
    assert_response :unprocessable_content
    put "/api/uploads/local", params: PNG, headers: auth.merge("CONTENT_TYPE" => "audio/mpeg", "X-Filename" => "x.mp3")
    assert_response :unprocessable_content
    put "/api/uploads/local", params: "", headers: auth.merge("CONTENT_TYPE" => "image/png", "X-Filename" => "x.png")
    assert_response :unprocessable_content
    assert_equal 3, Upload.count
  end

  test "a disk upload used by a deleted work sample is purged" do
    put "/api/uploads/local", params: PNG, headers: auth.merge("CONTENT_TYPE" => "image/png", "X-Filename" => "cover.png")
    assert_response :created
    url = response.parsed_body["url"]
    key = Upload.find(response.parsed_body["id"]).key
    id = create_sample(url, kind: "project")
    perform_enqueued_jobs { delete "/api/portfolio/#{id}", headers: auth }
    assert_nil ActiveStorage::Blob.find_by(key:)
    assert_not ActiveStorage::Blob.service.exist?(key), "file removed from disk"
    assert_equal 0, Upload.count
  end

  private

  def with_bucket(endpoint: nil, public_base: nil)
    ENV.update("AWS_BUCKET" => "verse-test", "AWS_ACCESS_KEY_ID" => "test-access", "AWS_SECRET_ACCESS_KEY" => "test-secret")
    endpoint ? ENV["AWS_ENDPOINT_URL_S3"] = endpoint : ENV.delete("AWS_ENDPOINT_URL_S3")
    public_base ? ENV["AWS_PUBLIC_BASE_URL"] = public_base : ENV.delete("AWS_PUBLIC_BASE_URL")
    UploadStorage.stub(:client, fake_client(endpoint)) { yield }
  end

  def fake_client(endpoint)
    options = { stub_responses: true, region: endpoint ? "auto" : "ap-south-1", credentials: Aws::Credentials.new("test-access", "test-secret") }
    options.merge!(endpoint:, force_path_style: true) if endpoint
    client = Aws::S3::Client.new(**options)
    objects = @objects
    client.stub_responses(:head_object, lambda { |context|
      object = objects[context.params[:key]]
      object ? { content_length: object[:body].bytesize, content_type: object[:type] } : "NotFound"
    })
    client.stub_responses(:get_object, lambda { |context|
      object = objects[context.params[:key]] or next "NoSuchKey"
      last = context.params[:range].to_s[/-(\d+)\z/, 1].to_i
      { body: object[:body].byteslice(0, last + 1) }
    })
    client.stub_responses(:delete_object, ->(context) { objects.delete(context.params[:key]) && {} || {} })
    client.stub_responses(:list_objects_v2, lambda { |_context|
      { contents: objects.map { |key, object| { key:, last_modified: object[:at] || Time.current } }, is_truncated: false }
    })
    client
  end

  def presign(filename, type, size)
    post "/api/uploads/presign", params: { filename:, contentType: type, size: }, headers: auth, as: :json
    assert_response :success
    Upload.find(response.parsed_body.fetch("id"))
  end

  def completed_direct_upload
    upload = presign("take.mp3", "audio/mpeg", MP3.bytesize)
    @objects[upload.key] = { body: MP3, type: "audio/mpeg" }
    post "/api/uploads/#{upload.id}/complete", headers: auth
    assert_response :success
    upload.reload
  end

  def create_sample(url, kind: "audio")
    post "/api/portfolio", params: { type: kind, title: "Sample", url: }, headers: auth, as: :json
    assert_response :created, response.body
    response.parsed_body.fetch("id")
  end

  def assert_rejected_sample(url, message)
    post "/api/portfolio", params: { type: "audio", title: "Sample", url: }, headers: auth, as: :json
    assert_response :unprocessable_content
    assert_match message, response.parsed_body["error"]
  end

  def create_user(label)
    user = User.create!(name: "Upload #{label}", email: "upload-#{label}-#{SecureRandom.hex(6)}@example.invalid",
      password: "StrongPass123!", role: "jobseeker", status: "active")
    token = SecureRandom.urlsafe_base64(48)
    user.sessions.create!(token_digest: Digest::SHA256.hexdigest(token), expires_at: 1.day.from_now)
    [user, token]
  end

  def auth = { "Authorization" => "Bearer #{@token}" }
  def other_auth = { "Authorization" => "Bearer #{@other_token}" }
end
