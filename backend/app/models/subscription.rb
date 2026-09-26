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

  # Razorpay sends the billing cycle as unix seconds (`current_start`/`current_end`).
  # Periods only move forward so a late or replayed event cannot shorten access,
  # and a terminal subscription is never extended.
  def apply_provider_period!(entity)
    period_start = unix_time(entity["current_start"])
    period_end = unix_time(entity["current_end"])
    return :ignored unless period_start && period_end && period_end > period_start

    with_lock do
      return :ignored if status == "cancelled"
      return :stale if current_period_end.present? && period_end <= current_period_end

      update!(current_period_start: period_start, current_period_end: period_end)
      :applied
    end
  end

  private

  def unix_time(value)
    return nil if value.blank? || !value.to_s.match?(/\A\d+\z/)

    Time.at(value.to_i).utc
  end
end
