class HardenFinancialIntegrity < ActiveRecord::Migration[7.2]
  CHECKS = {
    booking_payments_amount_positive: ["booking_payments", "amount > 0"],
    booking_payments_currency_format: ["booking_payments", "currency ~ '^[A-Z]{3}$'"],
    booking_payments_kind_valid: ["booking_payments", "kind IN ('deposit', 'balance', 'refund')"],
    booking_payments_provider_valid: ["booking_payments", "provider IN ('internal', 'razorpay')"],
    booking_payments_status_valid: ["booking_payments", "status IN ('created', 'paid', 'failed', 'refunded')"],
    subscriptions_provider_valid: ["subscriptions", "provider IN ('internal', 'razorpay')"],
    subscriptions_status_valid: ["subscriptions", "status IN ('pending', 'trialing', 'active', 'past_due', 'cancelled')"],
    booking_quotes_fees_nonnegative: ["booking_quotes", "performance_fee >= 0 AND travel_fee >= 0 AND production_fee >= 0 AND other_fee >= 0"],
    booking_quotes_deposit_percent_valid: ["booking_quotes", "deposit_percent BETWEEN 1 AND 100"],
    booking_requests_status_valid: ["booking_requests", "status IN ('requested', 'viewed', 'negotiating', 'quoted', 'accepted', 'completed', 'disputed', 'declined', 'cancelled')"]
  }.freeze

  def up
    add_column :subscriptions, :provider_state_at, :datetime
    add_column :subscriptions, :last_provider_event_id, :string
    add_column :booking_payments, :provider_state_at, :datetime
    add_column :booking_payments, :last_provider_event_id, :string
    add_column :billing_events, :processing_result, :string

    invalid = CHECKS.filter_map do |name, (table, expression)|
      count = select_value("SELECT COUNT(*) FROM #{quote_table_name(table)} WHERE NOT (#{expression})").to_i
      "#{name}=#{count}" if count.positive?
    end
    raise ActiveRecord::MigrationError, "Financial integrity preflight failed: #{invalid.join(', ')}" if invalid.any?

    CHECKS.each do |name, (table, expression)|
      add_check_constraint table, expression, name:, validate: false
      validate_check_constraint table, name:
    end
  end

  def down
    CHECKS.each { |name, config| remove_check_constraint config.first, name: }
    remove_column :booking_payments, :last_provider_event_id
    remove_column :booking_payments, :provider_state_at
    remove_column :billing_events, :processing_result
    remove_column :subscriptions, :last_provider_event_id
    remove_column :subscriptions, :provider_state_at
  end
end
