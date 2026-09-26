# Shared by the synthetic/demo data tests: proves a purge left nothing behind in ANY table
# that references a removed user, discovered from database foreign keys and model
# belongs_to reflections rather than a hand-maintained list.
module SyntheticTraceAssertions
  # Columns without a foreign key constraint that can still hold a user id.
  LOOSE_USER_COLUMNS = [%w[recent_activities entity_id], %w[reports entity_id], %w[audit_logs entity_id]].freeze

  def user_reference_columns
    connection = ActiveRecord::Base.lease_connection
    from_foreign_keys = connection.tables.flat_map do |table|
      connection.foreign_keys(table).select { _1.to_table == "users" }.map { |fk| [table, fk.column] }
    end
    Rails.application.eager_load!
    from_models = ApplicationRecord.descendants.reject(&:abstract_class?).flat_map do |model|
      model.reflect_on_all_associations(:belongs_to).reject(&:polymorphic?)
        .select { |reflection| reflection.klass == User }
        .map { |reflection| [model.table_name, reflection.foreign_key.to_s] }
    end
    (from_foreign_keys + from_models + LOOSE_USER_COLUMNS).uniq
  end

  def assert_no_user_traces(user_ids)
    assert user_ids.any?, "expected some removed users to check"
    connection = ActiveRecord::Base.lease_connection
    columns = user_reference_columns
    assert_operator columns.size, :>=, 40, "user reference discovery looks incomplete: #{columns.inspect}"
    columns.each do |table, column|
      sql = ApplicationRecord.sanitize_sql_array(["SELECT COUNT(*) FROM #{connection.quote_table_name(table)} WHERE #{connection.quote_column_name(column)} IN (?)", user_ids])
      assert_equal 0, connection.select_value(sql).to_i, "#{table}.#{column} still references a purged user"
    end
    assert_equal 0, User.where(id: user_ids).count
  end
end
