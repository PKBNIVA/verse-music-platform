class AddProductionIndexes < ActiveRecord::Migration[7.2]
  def change
    enable_extension "pg_trgm"

    add_index :jobs, :title, using: :gin, opclass: :gin_trgm_ops
    add_index :jobs, :company, using: :gin, opclass: :gin_trgm_ops
    add_index :acts, :name, using: :gin, opclass: :gin_trgm_ops
    add_index :messages, %i[conversation_id created_at]
    add_index :notifications, %i[user_id read_at created_at]
    add_index :subscriptions, :provider_subscription_id, unique: true, where: "provider_subscription_id IS NOT NULL"
    add_index :booking_payments, :provider_order_id, unique: true, where: "provider_order_id IS NOT NULL"
    add_index :booking_payments, :provider_payment_id, unique: true, where: "provider_payment_id IS NOT NULL"
  end
end
