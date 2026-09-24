class Subscription < ApplicationRecord
  STATUSES = %w[pending trialing active past_due cancelled].freeze
  PROVIDERS = %w[internal razorpay].freeze
  PROVIDER_TRANSITIONS = {
    "pending" => %w[pending trialing active past_due cancelled],
    "trialing" => %w[trialing active past_due cancelled],
    "active" => %w[active past_due cancelled],
    "past_due" => %w[past_due active cancelled],
    "cancelled" => %w[cancelled]
  }.freeze
  STATUS_PRIORITY = { "pending" => 0, "trialing" => 1, "past_due" => 2, "active" => 3, "cancelled" => 4 }.freeze

  belongs_to :user

  validates :plan_code, :provider, :status, presence: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  def apply_provider_status!(new_status:, event_at:, event_id:)
    raise ArgumentError, "unsupported provider status" unless STATUSES.include?(new_status)

    with_lock do
      return :stale if provider_state_at.present? && event_at < provider_state_at
      return :stale if provider_state_at == event_at && STATUS_PRIORITY.fetch(new_status) <= STATUS_PRIORITY.fetch(status)
      return :invalid_transition unless PROVIDER_TRANSITIONS.fetch(status, []).include?(new_status)

      update!(status: new_status, provider_state_at: event_at, last_provider_event_id: event_id)
      :applied
    end
  end
end
