require "test_helper"

class ReadinessChecksTest < ActiveSupport::TestCase
  test "database readiness executes a real query" do
    queried = false
    connection = fake_connection { |sql| queried = sql == "SELECT 1"; 1 }

    checks = ReadinessChecks.new(connection_provider: -> { connection }).call
    assert queried
    assert_equal true, checks.dig(:database, :ok)
  end

  test "database query failure makes core readiness fail" do
    connection = fake_connection { raise ActiveRecord::ConnectionNotEstablished }

    checker = ReadinessChecks.new(connection_provider: -> { connection })
    checks = checker.call
    assert_equal false, checks.dig(:database, :ok)
    assert_equal false, checker.core_ready?(checks)
  end

  test "optional integration state does not change core readiness" do
    checker = ReadinessChecks.new
    checks = {
      database: { ok: true, required: true },
      payments: { ok: false, required: false }
    }

    assert checker.core_ready?(checks)
    assert_not checker.optional_integrations_ready?(checks)
  end

  private

  def fake_connection(&query)
    Object.new.tap do |connection|
      connection.define_singleton_method(:adapter_name) { "PostgreSQL" }
      connection.define_singleton_method(:transaction) { |**_, &block| block.call }
      connection.define_singleton_method(:execute) { |_sql| true }
      connection.define_singleton_method(:select_value, &query)
    end
  end
end
