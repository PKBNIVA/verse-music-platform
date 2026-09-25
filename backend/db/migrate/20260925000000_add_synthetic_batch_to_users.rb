class AddSyntheticBatchToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :synthetic_batch, :string
    add_index :users, :synthetic_batch, where: "synthetic_batch IS NOT NULL"
  end
end
