class CreateBillingAttempts < ActiveRecord::Migration[7.2]
  def change
    create_table :billing_attempts, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :operation, :provider, :idempotency_key, :state, null: false
      t.string :resource_type, :resource_id, :provider_resource_id
      t.jsonb :request_payload, default: {}, null: false
      t.jsonb :response_payload, default: {}, null: false
      t.string :error_code
      t.text :error_message
      t.datetime :last_attempted_at, :reconciled_at
      t.timestamps
    end

    add_index :billing_attempts, :idempotency_key, unique: true
    add_index :billing_attempts, %i[resource_type resource_id]
    add_index :billing_attempts, %i[state created_at]
  end
end
