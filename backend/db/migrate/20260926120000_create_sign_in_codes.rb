# One-time email sign-in codes (passwordless OTP). A separate table rather than
# email_tokens because a sign-up code exists before its user does
# (email_tokens.user_id is NOT NULL), and codes need an attempt counter and the
# pending sign-up name/role.
#
# Lock profile: creates a new, empty table; no existing table is read, rewritten or
# locked. Rollback drops the table; outstanding codes are lost and users simply
# request a new one (password login is unaffected).
class CreateSignInCodes < ActiveRecord::Migration[7.2]
  def change
    create_table :sign_in_codes, id: :string do |t|
      t.citext :email, null: false
      t.string :code_digest, null: false
      t.string :pending_name
      t.string :pending_role
      t.integer :attempts, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :sign_in_codes, [:email, :created_at]
    add_index :sign_in_codes, :expires_at
  end
end
