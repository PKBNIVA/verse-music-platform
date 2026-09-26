# Records every stored upload object so the API can verify it (size and magic bytes),
# restrict portfolio URLs to the uploader's own completed files, and delete objects
# when they are no longer referenced.
#
# Lock profile: creates a new, empty table. The only lock on an existing table is the
# brief SHARE ROW EXCLUSIVE lock on `users` taken while adding the foreign key (it
# blocks writes to users for milliseconds, never reads). lock_timeout makes the
# migration fail fast instead of queueing behind a long transaction.
#
# `user_id` is nullable with ON DELETE SET NULL: deleting a user (including the
# synthetic-QA bulk purge, which bypasses callbacks) never fails on this table, and the
# daily UploadSweepJob deletes the objects of uploads whose owner is gone.
#
# Rollback drops the table. Objects already in storage are not touched; after a
# rollback they are simply untracked (the previous release never tracked them either).
class CreateUploads < ActiveRecord::Migration[7.2]
  def change
    reversible { |direction| direction.up { execute "SET LOCAL lock_timeout = '5s'" } }

    create_table :uploads, id: :string do |t|
      t.string :user_id
      t.string :storage, null: false
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :status, null: false, default: "pending"
      t.string :public_url
      t.datetime :completed_at
      t.timestamps
    end

    add_index :uploads, %i[storage key], unique: true
    add_index :uploads, %i[user_id status]
    add_index :uploads, %i[status created_at]
    add_index :uploads, :public_url
    add_foreign_key :uploads, :users, on_delete: :nullify
  end
end
