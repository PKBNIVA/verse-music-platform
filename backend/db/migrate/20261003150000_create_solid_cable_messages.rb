# Action Cable's message table for the Solid Cable adapter (config/cable.yml), on the main
# database. Rows are broadcasts in flight; Solid Cable trims anything older than
# solid_cable_retention_hours (config/realtime.yml). Holds ids and states only, no message text.
class CreateSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, limit: 1024, null: false
      t.binary :payload, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.bigint :channel_hash, null: false
      t.index :channel
      t.index :channel_hash
      t.index :created_at
    end
  end
end
