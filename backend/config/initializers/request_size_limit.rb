# Caps request bodies so a single oversized JSON payload cannot tie up a Puma thread or memory.
# Streamed file uploads (PUT /api/uploads/local) keep their own, larger limit in UploadsController.
class RequestSizeLimit
  DEFAULT_LIMIT = 1.megabyte
  UPLOAD_PATH = "/api/uploads/local".freeze

  def initialize(app, limit: DEFAULT_LIMIT)
    @app = app
    @limit = limit
  end

  def call(env)
    return @app.call(env) if env["PATH_INFO"] == UPLOAD_PATH

    declared = env["CONTENT_LENGTH"].presence&.to_i
    return too_large if declared && declared > @limit
    return too_large if declared.nil? && chunked_body_over_limit?(env)

    @app.call(env)
  end

  private

  # Chunked bodies carry no Content-Length; read at most one byte past the limit, then rewind.
  def chunked_body_over_limit?(env)
    input = env["rack.input"]
    return false unless input && env["HTTP_TRANSFER_ENCODING"].to_s.downcase.include?("chunked")

    over = input.read(@limit + 1).to_s.bytesize > @limit
    input.rewind if input.respond_to?(:rewind)
    over
  end

  def too_large
    body = { error: "Request is too large.", code: "PAYLOAD_TOO_LARGE" }.to_json
    [413, { "content-type" => "application/json", "content-length" => body.bytesize.to_s }, [body]]
  end
end

# After CORS so a rejected browser request still carries the CORS headers and its 413 is readable.
Rails.application.config.middleware.insert_after Rack::Cors, RequestSizeLimit
