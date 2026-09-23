class EnforceSingleActiveBookingPayment < ActiveRecord::Migration[7.2]
  def change
    add_index :booking_payments, %i[booking_request_id kind], unique: true,
      where: "status IN ('created', 'paid')", name: "index_booking_payments_on_active_kind"
  end
end
