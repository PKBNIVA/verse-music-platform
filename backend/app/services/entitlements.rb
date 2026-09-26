# Server-side plan capacity for a user, derived from Billing::BillingController::PLANS.
#
# A subscription grants its plan only while it is effective:
# - `active`, or `trialing` with a trial end in the future (or none recorded);
# - an internal (mock or admin-granted) subscription with a `current_period_end`
#   stops granting access once that period has ended.
# `pending`, `past_due` and `cancelled` never grant paid capacity (see SAAS_BILLING.md).
class Entitlements
  LIMITS = { active_posts: :activePosts, seats: :seats, shortlist: :shortlist, bookings: :bookings }.freeze
  PLAN_RANK = { "free" => 0, "pro" => 1, "studio" => 2, "enterprise" => 3 }.freeze
  # Booking enquiries that still occupy capacity for the requester.
  ACTIVE_BOOKING_STATUSES = %w[requested viewed negotiating quoted accepted].freeze
  ERROR_CODE = "PLAN_LIMIT_REACHED".freeze

  class LimitReached < StandardError
    attr_reader :limit_key, :limit

    def initialize(limit_key, limit)
      @limit_key = limit_key
      @limit = limit
      super("Your plan allows #{limit} #{LABELS.fetch(limit_key)}. Upgrade your plan to add more.")
    end
  end

  LABELS = { active_posts: "active opportunities", seats: "workspace seats", shortlist: "saved talent", bookings: "active booking enquiries" }.freeze

  def self.for(user, now: Time.current) = new(user, now:)

  def self.plans = Billing::BillingController::PLANS

  def initialize(user, now: Time.current)
    @user = user
    @now = now
  end

  def subscription
    return @subscription if defined?(@subscription)

    candidates = @user ? Subscription.where(user: @user, status: %w[active trialing]).order(created_at: :desc).to_a : []
    @subscription = candidates.select { effective?(_1) }.max_by { [PLAN_RANK.fetch(_1.plan_code, 0), _1.created_at] }
  end

  def plan_code
    code = subscription&.plan_code
    self.class.plans.key?(code) ? code : "free"
  end

  def plan = self.class.plans.fetch(plan_code)

  def limit(key) = plan.fetch(LIMITS.fetch(key))

  def allows?(key, current_count) = current_count < limit(key)

  def ensure_capacity!(key, current_count)
    raise LimitReached.new(key, limit(key)) unless allows?(key, current_count)
  end

  def effective?(sub)
    return false unless %w[active trialing].include?(sub.status)
    return false if sub.status == "trialing" && sub.trial_ends_at.present? && sub.trial_ends_at <= @now
    return false if sub.provider == "internal" && sub.current_period_end.present? && sub.current_period_end <= @now

    true
  end
end
