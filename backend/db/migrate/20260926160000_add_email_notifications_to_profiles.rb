# Per-user opt-out for notification emails (messages, bookings, application updates).
# Transactional/security emails (sign-in codes, verification, password reset) ignore it.
#
# Lock profile: ADD COLUMN with a constant default is metadata-only on PostgreSQL 11+
# (no table rewrite); it takes a brief ACCESS EXCLUSIVE lock on `profiles`, and
# lock_timeout makes the migration fail fast instead of queueing behind a long transaction.
#
# Rollback (`bin/rails db:migrate:down VERSION=20260926160000`) drops the column; every
# user then receives notification emails again, as before this release.
class AddEmailNotificationsToProfiles < ActiveRecord::Migration[7.2]
  def change
    reversible { |direction| direction.up { execute "SET LOCAL lock_timeout = '5s'" } }

    add_column :profiles, :email_notifications, :boolean, default: true, null: false
  end
end
