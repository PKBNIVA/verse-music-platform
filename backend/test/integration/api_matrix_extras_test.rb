require "test_helper"
require_relative "../support/api_matrix_world"
require "minitest/mock"
require "aws-sdk-s3"

# Matrix cases that need environment switches or storage stubs, kept out of the generated
# route x role matrix: the Razorpay simulator routes, demo-data batch guards and completing a
# pending direct upload.
class ApiMatrixExtrasTest < ActionDispatch::IntegrationTest
  include ApiMatrixAssertions
  include ActiveJob::TestHelper

  SIM_ENV = %w[RAZORPAY_SIMULATOR RAZORPAY_KEY_ID RAZORPAY_KEY_SECRET AWS_BUCKET AWS_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY].freeze
  DEV_ROUTES = [
    [:post, "/api/dev/razorpay/checkout"],
    [:post, "/api/dev/razorpay/subscriptions/sub_x/activate"],
    [:post, "/api/dev/razorpay/payments/pay_x/refund"],
    [:post, "/api/dev/razorpay/webhooks"]
  ].freeze

  setup do
    @saved_env = SIM_ENV.to_h { [_1, ENV[_1]] }
    @world = ApiMatrixWorld.build
  end

  teardown { @saved_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value } }

  test "dev Razorpay simulator routes 404 for everyone unless the simulator is on" do
    ENV.delete("RAZORPAY_SIMULATOR")
    DEV_ROUTES.each do |verb, path|
      [nil, :js, :admin].each do |actor|
        public_send(verb, path, params: {}, headers: @world.headers(actor), as: :json)
        assert_equal 404, response.status, "#{verb} #{path} as #{actor || 'anonymous'} with the simulator off"
      end
    end
  end

  test "dev Razorpay simulator routes exist with the simulator on and still require sign-in" do
    enable_simulator
    DEV_ROUTES.each do |verb, path|
      public_send(verb, path, params: {}, as: :json)
      assert_equal 401, response.status, "#{verb} #{path} anonymous with the simulator on"
      assert_error_shape(path)
    end
    post "/api/dev/razorpay/checkout", params: { outcome: "explode" }, headers: @world.headers(:js), as: :json
    assert_equal 400, response.status
  end

  test "dev Razorpay simulator routes 404 in production even with the simulator variables set" do
    enable_simulator
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_not RazorpayConfig.simulator?
      DEV_ROUTES.each do |verb, path|
        public_send(verb, path, params: {}, headers: @world.headers(:admin), as: :json)
        assert_equal 404, response.status, "#{verb} #{path} in production"
      end
    end
  end

  test "demo-data batch deletion only accepts existing demo-* batches" do
    admin = @world.headers(:admin)
    delete "/api/admin/demo-data/perf", headers: admin
    assert_equal [422, "NOT_A_DEMO_BATCH"], [response.status, response.parsed_body["code"]]
    delete "/api/admin/demo-data/demo-19990101-0000", headers: admin
    assert_equal 404, response.status
    assert_error_shape("missing demo batch")
    delete "/api/admin/demo-data/#{@world.refs[:shared][:demo_batch]}", headers: admin
    assert_equal 202, response.status
    assert_enqueued_jobs 1
    post "/api/admin/demo-data", params: { size: "small" }, headers: admin, as: :json
    assert_equal [409, "DEMO_JOB_RUNNING"], [response.status, response.parsed_body["code"]], "one demo job at a time"
    get "/api/admin/demo-data/jobs/#{response.parsed_body['jobId'] || 'x'}", headers: admin
    assert_includes [200, 404], response.status
  end

  test "completing a pending direct upload: owner only, verified against storage" do
    ENV["AWS_BUCKET"] = "matrix-bucket"
    js = @world.user(:js)
    header = "ID3".b + ("\x00".b * 29)
    upload = Upload.create!(user: js, storage: "s3", key: "uploads/#{js.id}/x/take.mp3", filename: "take.mp3", content_type: "audio/mpeg",
      byte_size: header.bytesize, status: "pending", public_url: "https://cdn.example.com/take.mp3")

    post "/api/uploads/#{upload.id}/complete", headers: @world.headers(:js2), as: :json
    assert_equal 404, response.status, "another user's pending upload"
    delete "/api/uploads/#{upload.id}", headers: @world.headers(:emp)
    assert_equal 404, response.status

    UploadStorage.stub(:inspect_object, nil) do
      post "/api/uploads/#{upload.id}/complete", headers: @world.headers(:js), as: :json
    end
    assert_equal [409, "UPLOAD_NOT_FOUND"], [response.status, response.parsed_body["code"]]

    UploadStorage.stub(:inspect_object, { size: header.bytesize, content_type: "audio/mpeg", header: }) do
      post "/api/uploads/#{upload.id}/complete", headers: @world.headers(:js), as: :json
    end
    assert_equal 200, response.status, response.body
    assert_keys response.parsed_body, %w[upload url], "uploads complete"
    assert_keys response.parsed_body["upload"], %w[id url status contentType byteSize filename], "uploads complete upload"
    assert_equal "complete", upload.reload.status
  end

  test "direct-mode presign returns the fields uploadMedia reads" do
    ENV.update("AWS_BUCKET" => "matrix-bucket", "AWS_REGION" => "ap-south-1", "AWS_ACCESS_KEY_ID" => "test-access", "AWS_SECRET_ACCESS_KEY" => "test-secret")
    client = Aws::S3::Client.new(stub_responses: true, region: "ap-south-1", credentials: Aws::Credentials.new("test-access", "test-secret"))
    UploadStorage.stub(:client, client) do
      post "/api/uploads/presign", params: { filename: "take.mp3", contentType: "audio/mpeg", size: 1234 }, headers: @world.headers(:js), as: :json
    end
    assert_equal 200, response.status, response.body
    assert_keys response.parsed_body, %w[mode id uploadUrl publicUrl completeUrl expiresIn], "uploads presign (direct)"
    assert_equal "direct", response.parsed_body["mode"]
    assert_equal "/api/uploads/#{response.parsed_body['id']}/complete", response.parsed_body["completeUrl"]
    assert_equal "pending", Upload.find(response.parsed_body["id"]).status
  end

  private

  def enable_simulator
    ENV.update("RAZORPAY_SIMULATOR" => "true", "RAZORPAY_KEY_ID" => "rzp_test_matrix", "RAZORPAY_KEY_SECRET" => "sim_secret_matrix")
  end
end
