# The original schema declared `kind`, `evidence_url` and `status` together with
# `null: false, default: "pending"`, so evidence became mandatory (a request without
# it raised NotNullViolation -> 500) and `kind`/`evidence_url` silently defaulted to
# the status value "pending". `status` keeps its default; the other two lose it.
#
# Lock profile: DROP NOT NULL and SET/DROP DEFAULT are catalog-only changes (no table
# rewrite or scan) but still take a brief ACCESS EXCLUSIVE lock. lock_timeout makes the
# migration fail fast instead of queueing behind a long transaction and blocking reads.
# Rolling back re-adds NOT NULL, which scans the (small) table under that lock; rows
# without evidence are backfilled with an empty string first so the rollback succeeds.
class RelaxVerificationRequestEvidence < ActiveRecord::Migration[7.2]
  def change
    reversible { |direction| direction.up { execute "SET LOCAL lock_timeout = '5s'" } }

    change_column_default :verification_requests, :kind, from: "pending", to: nil
    change_column_default :verification_requests, :evidence_url, from: "pending", to: nil
    change_column_null :verification_requests, :evidence_url, true

    reversible do |direction|
      # Rollback runs this first, before change_column_null(..., false) re-adds NOT NULL.
      direction.down do
        execute "SET LOCAL lock_timeout = '5s'"
        execute "UPDATE verification_requests SET evidence_url = '' WHERE evidence_url IS NULL"
      end
    end
  end
end
