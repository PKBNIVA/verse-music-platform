# Fixed-window per-user rate limit backed by Rails.cache (memory store per process
# unless REDIS_URL is configured). Fails open if the cache is unavailable.
module UserRateLimit
  extend ActiveSupport::Concern

  private

  # Returns true when the request may proceed; otherwise renders 429 and returns false.
  def within_user_rate_limit?(bucket, limit:, period:)
    window = Time.current.to_i / period.to_i
    key = "user-rate:#{bucket}:#{current_user.id}:#{window}"
    count = Rails.cache.increment(key, 1, expires_in: period)
    return true if count.nil? || count <= limit

    response.set_header("Retry-After", (period.to_i - (Time.current.to_i % period.to_i)).to_s)
    render_error("You're doing that too often. Try again later.", :too_many_requests, "RATE_LIMITED")
    false
  end
end
