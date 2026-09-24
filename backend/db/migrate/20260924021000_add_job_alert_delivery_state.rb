class AddJobAlertDeliveryState < ActiveRecord::Migration[7.2]
  def change
    add_column :job_alerts, :last_run_at, :datetime
    add_column :job_alerts, :next_run_at, :datetime
    add_index :job_alerts, %i[active next_run_at]
    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE job_alerts
          SET next_run_at = CURRENT_TIMESTAMP + CASE frequency
            WHEN 'daily' THEN INTERVAL '1 day'
            WHEN 'weekly' THEN INTERVAL '7 days'
          END
          WHERE active = TRUE AND frequency IN ('daily', 'weekly') AND next_run_at IS NULL
        SQL
      end
    end

    create_table :job_alert_deliveries, id: :string do |t|
      t.references :job_alert, type: :string, null: false, foreign_key: true
      t.references :job, type: :string, null: false, foreign_key: true
      t.references :notification, type: :string, null: true, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
    add_index :job_alert_deliveries, %i[job_alert_id job_id], unique: true
  end
end
