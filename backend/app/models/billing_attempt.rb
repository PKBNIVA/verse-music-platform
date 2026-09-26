class BillingAttempt < ApplicationRecord
  OPERATIONS = %w[subscription_create booking_order_create].freeze
  STATES = %w[pending succeeded ambiguous failed].freeze

  belongs_to :user
  attribute :request_payload, :json, default: -> { {} }
  attribute :response_payload, :json, default: -> { {} }

  validates :operation, inclusion: { in: OPERATIONS }
  validates :state, inclusion: { in: STATES }
  validates :provider, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: true

  def succeed!(provider_resource_id:, response_payload: {})
    update!(state: "succeeded", provider_resource_id:, response_payload:, error_code: nil, error_message: nil, reconciled_at: Time.current)
  end

  STALE_AFTER = 30.minutes
  IN_FLIGHT_WINDOW = 2.minutes

  scope :unresolved, -> { where(state: %w[pending ambiguous]) }

  def mark_stale!(now: Time.current)
    update!(state: "failed", error_code: "stale", error_message: "No provider resource was recorded within #{STALE_AFTER.inspect}.", last_attempted_at: now)
  end

  def fail_from!(error)
    update!(state: error.ambiguous? ? "ambiguous" : "failed", error_code: error.code, error_message: error.message, last_attempted_at: Time.current)
  end
end
