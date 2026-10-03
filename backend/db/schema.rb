# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_03_160000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"

  create_table "act_invites", id: :string, force: :cascade do |t|
    t.string "act_id", null: false
    t.string "inviter_id", null: false
    t.string "kind", null: false
    t.string "invitee_user_id"
    t.citext "invitee_email"
    t.string "role_name", null: false
    t.string "instrument"
    t.string "token_digest", null: false
    t.string "status", default: "pending", null: false
    t.datetime "expires_at", null: false
    t.datetime "responded_at"
    t.string "accepted_by_id"
    t.datetime "last_sent_at"
    t.integer "send_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["act_id", "status"], name: "index_act_invites_on_act_id_and_status"
    t.index ["invitee_email", "status"], name: "index_act_invites_on_invitee_email_and_status"
    t.index ["invitee_user_id", "status"], name: "index_act_invites_on_invitee_user_id_and_status"
    t.index ["inviter_id"], name: "index_act_invites_on_inviter_id"
    t.index ["token_digest"], name: "index_act_invites_on_token_digest", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['user'::character varying, 'email'::character varying, 'link'::character varying]::text[])", name: "act_invites_kind_valid"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'accepted'::character varying, 'declined'::character varying, 'revoked'::character varying]::text[])", name: "act_invites_status_valid"
  end

  create_table "act_members", id: :string, force: :cascade do |t|
    t.string "act_id", null: false
    t.string "user_id"
    t.string "display_name", null: false
    t.string "role_name", null: false
    t.string "member_status", null: false
    t.string "instrument"
    t.boolean "is_leader", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["act_id"], name: "index_act_members_on_act_id"
    t.index ["user_id"], name: "index_act_members_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "acts", id: :string, force: :cascade do |t|
    t.string "owner_id", null: false
    t.string "name", null: false
    t.string "act_type", null: false
    t.string "currency", null: false
    t.string "fee_basis", null: false
    t.string "status", null: false
    t.string "tagline"
    t.string "city"
    t.string "tech_rider_url"
    t.string "hospitality_rider_url"
    t.string "promo_url"
    t.text "bio"
    t.jsonb "genres", default: [], null: false
    t.jsonb "languages", default: [], null: false
    t.jsonb "event_types", default: [], null: false
    t.integer "lineup_size", default: 1, null: false
    t.integer "min_fee"
    t.integer "max_fee"
    t.integer "travel_radius_km"
    t.boolean "travels_nationally", default: false, null: false
    t.boolean "travels_internationally", default: false, null: false
    t.boolean "verified", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "photo_url"
    t.tsvector "search_vector"
    t.text "search_text"
    t.index "((event_types)::text) gin_trgm_ops", name: "index_acts_on_event_types_text_trgm", using: :gin
    t.index "((genres)::text) gin_trgm_ops", name: "index_acts_on_genres_text_trgm", using: :gin
    t.index ["bio"], name: "index_acts_on_bio", opclass: :gin_trgm_ops, using: :gin
    t.index ["name"], name: "index_acts_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["owner_id"], name: "index_acts_on_owner_id"
    t.index ["search_text"], name: "index_acts_on_search_text_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_vector"], name: "index_acts_on_search_vector", using: :gin
    t.index ["tagline"], name: "index_acts_on_tagline", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "ai_batch_classifications", id: :string, force: :cascade do |t|
    t.string "portfolio_item_id", null: false
    t.string "account_type", null: false
    t.string "account_id", null: false
    t.string "status", default: "queued", null: false
    t.string "batch_id"
    t.string "custom_id"
    t.jsonb "input_context", default: {}, null: false
    t.jsonb "result"
    t.string "error"
    t.datetime "submitted_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_ai_batch_classifications_on_batch_id"
    t.index ["portfolio_item_id"], name: "index_ai_batch_classifications_on_portfolio_item_id"
    t.index ["status"], name: "index_ai_batch_classifications_on_status"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying::text, 'submitted'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text])", name: "ai_batch_classifications_status_valid"
  end

  create_table "ai_credit_ledgers", id: :string, force: :cascade do |t|
    t.string "account_type", null: false
    t.string "account_id", null: false
    t.integer "delta", null: false
    t.string "reason", null: false
    t.string "task"
    t.string "period"
    t.decimal "cost_inr", precision: 10, scale: 4, default: "0.0", null: false
    t.integer "tokens_in"
    t.integer "tokens_out"
    t.boolean "cached", default: false, null: false
    t.boolean "batch", default: false, null: false
    t.datetime "expires_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.index ["account_type", "account_id", "created_at"], name: "idx_on_account_type_account_id_created_at_c06154401d"
    t.index ["account_type", "account_id", "period"], name: "index_ai_credit_ledgers_on_account_and_period"
    t.index ["account_type", "account_id", "reason", "period"], name: "index_ai_credit_ledgers_unique_allowance_per_period", unique: true, where: "((reason)::text = 'monthly_allowance'::text)"
    t.check_constraint "account_type::text = ANY (ARRAY['user'::character varying::text, 'organization'::character varying::text])", name: "ai_credit_ledgers_account_type_valid"
    t.check_constraint "reason::text = ANY (ARRAY['monthly_allowance'::character varying::text, 'usage'::character varying::text, 'refund'::character varying::text, 'topup'::character varying::text, 'admin_grant'::character varying::text, 'expiry'::character varying::text])", name: "ai_credit_ledgers_reason_valid"
  end

  create_table "ai_topup_payments", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "pack", null: false
    t.integer "amount", null: false
    t.string "currency", default: "INR", null: false
    t.string "provider", null: false
    t.string "status", default: "created", null: false
    t.string "provider_order_id"
    t.string "provider_payment_id"
    t.integer "credits", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider_order_id"], name: "index_ai_topup_payments_on_provider_order_id", unique: true, where: "(provider_order_id IS NOT NULL)"
    t.index ["provider_payment_id"], name: "index_ai_topup_payments_on_provider_payment_id", unique: true, where: "(provider_payment_id IS NOT NULL)"
    t.index ["user_id"], name: "index_ai_topup_payments_on_user_id"
    t.check_constraint "pack::text = ANY (ARRAY['small'::character varying::text, 'large'::character varying::text])", name: "ai_topup_payments_pack_valid"
    t.check_constraint "provider::text = ANY (ARRAY['internal'::character varying::text, 'razorpay'::character varying::text])", name: "ai_topup_payments_provider_valid"
    t.check_constraint "status::text = ANY (ARRAY['created'::character varying::text, 'paid'::character varying::text, 'failed'::character varying::text])", name: "ai_topup_payments_status_valid"
  end

  create_table "application_events", id: :string, force: :cascade do |t|
    t.string "application_id", null: false
    t.string "actor_id"
    t.string "event_type"
    t.string "from_status"
    t.string "to_status"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_application_events_on_actor_id"
    t.index ["application_id"], name: "index_application_events_on_application_id"
  end

  create_table "applications", id: :string, force: :cascade do |t|
    t.string "job_id", null: false
    t.string "candidate_id", null: false
    t.text "cover_letter"
    t.text "recruiter_note"
    t.string "status", default: "Applied", null: false
    t.datetime "interview_date"
    t.integer "recruiter_rating"
    t.jsonb "screening_answers", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "portfolio_id"
    t.string "resume_id"
    t.jsonb "materials_snapshot"
    t.index "((materials_snapshot #>> '{resume,uploadId}'::text[]))", name: "index_applications_on_snapshot_upload_id", where: "(materials_snapshot IS NOT NULL)"
    t.index ["candidate_id"], name: "index_applications_on_candidate_id"
    t.index ["job_id", "candidate_id"], name: "index_applications_on_job_id_and_candidate_id", unique: true
    t.index ["job_id"], name: "index_applications_on_job_id"
    t.index ["portfolio_id"], name: "index_applications_on_portfolio_id", where: "(portfolio_id IS NOT NULL)"
    t.index ["resume_id"], name: "index_applications_on_resume_id", where: "(resume_id IS NOT NULL)"
  end

  create_table "audit_logs", id: :string, force: :cascade do |t|
    t.string "actor_id"
    t.string "action", null: false
    t.string "entity_type"
    t.string "entity_id"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_audit_logs_on_actor_id"
  end

  create_table "auth_connections", id: :string, force: :cascade do |t|
    t.string "owner_type", null: false
    t.string "owner_id", null: false
    t.string "provider", null: false
    t.string "provider_uid", null: false
    t.citext "email"
    t.boolean "email_verified", default: false, null: false
    t.string "display_name"
    t.string "avatar_url"
    t.text "access_token"
    t.text "refresh_token"
    t.jsonb "scopes", default: [], null: false
    t.datetime "expires_at"
    t.jsonb "raw", default: {}, null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_auth_connections_on_owner"
    t.index ["provider", "provider_uid"], name: "index_auth_connections_on_provider_and_uid", unique: true
  end

  create_table "availability_windows", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.datetime "start_at", null: false
    t.datetime "end_at", null: false
    t.string "status", default: "available", null: false
    t.string "city"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_availability_windows_on_user_id"
  end

  create_table "badges", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "kind", null: false
    t.string "awarded_for", null: false
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "awarded_for"], name: "index_badges_on_kind_and_awarded_for"
    t.index ["user_id", "kind", "awarded_for"], name: "index_badges_on_user_kind_period", unique: true
  end

  create_table "band_project_roles", id: :string, force: :cascade do |t|
    t.string "band_project_id", null: false
    t.string "opportunity_id"
    t.string "role_name", null: false
    t.string "status", null: false
    t.string "instrument"
    t.string "skill_level"
    t.string "compensation"
    t.integer "count_needed", default: 1, null: false
    t.text "requirements"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["band_project_id"], name: "index_band_project_roles_on_band_project_id"
    t.index ["opportunity_id"], name: "index_band_project_roles_on_opportunity_id"
  end

  create_table "band_projects", id: :string, force: :cascade do |t|
    t.string "owner_id", null: false
    t.string "name", null: false
    t.string "status", null: false
    t.string "city"
    t.string "commitment_type"
    t.string "rehearsal_schedule"
    t.string "compensation_model"
    t.text "concept"
    t.jsonb "genres", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_band_projects_on_owner_id"
  end

  create_table "billing_attempts", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "operation", null: false
    t.string "provider", null: false
    t.string "idempotency_key", null: false
    t.string "state", null: false
    t.string "resource_type"
    t.string "resource_id"
    t.string "provider_resource_id"
    t.jsonb "request_payload", default: {}, null: false
    t.jsonb "response_payload", default: {}, null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "last_attempted_at"
    t.datetime "reconciled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_billing_attempts_on_idempotency_key", unique: true
    t.index ["resource_type", "resource_id"], name: "index_billing_attempts_on_resource_type_and_resource_id"
    t.index ["state", "created_at"], name: "index_billing_attempts_on_state_and_created_at"
    t.index ["user_id"], name: "index_billing_attempts_on_user_id"
  end

  create_table "billing_credits", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.integer "days", null: false
    t.string "reason", null: false
    t.string "promo_redemption_id"
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["promo_redemption_id"], name: "index_billing_credits_on_promo_redemption_id", unique: true, where: "(promo_redemption_id IS NOT NULL)"
    t.index ["user_id", "reason"], name: "index_billing_credits_on_user_and_reason"
    t.check_constraint "days > 0", name: "billing_credits_days_positive"
  end

  create_table "billing_events", id: :string, force: :cascade do |t|
    t.string "provider", null: false
    t.string "provider_event_id", null: false
    t.string "event_type", null: false
    t.string "user_id"
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "processing_result"
    t.index ["provider", "provider_event_id"], name: "index_billing_events_on_provider_and_provider_event_id", unique: true
    t.index ["user_id"], name: "index_billing_events_on_user_id"
  end

  create_table "billing_profiles", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.integer "version", null: false
    t.boolean "current", default: true, null: false
    t.string "buyer_type", default: "individual", null: false
    t.string "legal_name", null: false
    t.string "gstin"
    t.string "pan"
    t.string "address_line1", null: false
    t.string "address_line2"
    t.string "city", null: false
    t.string "state_code", null: false
    t.string "postal_code", null: false
    t.string "country", default: "India", null: false
    t.string "billing_email", null: false
    t.string "po_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "version"], name: "index_billing_profiles_on_user_id_and_version", unique: true
    t.index ["user_id"], name: "index_billing_profiles_on_user_id"
    t.index ["user_id"], name: "index_billing_profiles_one_current_per_user", unique: true, where: "current"
    t.check_constraint "buyer_type::text = ANY (ARRAY['individual'::character varying, 'business'::character varying]::text[])", name: "billing_profiles_buyer_type_valid"
  end

  create_table "billing_reminders", id: :string, force: :cascade do |t|
    t.string "subscription_id", null: false
    t.string "kind", null: false
    t.date "sent_on", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id", "kind", "sent_on"], name: "index_billing_reminders_on_sub_kind_date", unique: true
    t.check_constraint "kind::text = ANY (ARRAY['trial_ending'::character varying, 'renewal_ending'::character varying, 'early_access_7d'::character varying, 'early_access_1d'::character varying]::text[])", name: "billing_reminders_kind_valid"
  end

  create_table "booking_payments", id: :string, force: :cascade do |t|
    t.string "booking_request_id", null: false
    t.string "booking_quote_id"
    t.string "payer_id", null: false
    t.string "kind", null: false
    t.string "currency", null: false
    t.string "provider", null: false
    t.string "status", null: false
    t.string "provider_order_id"
    t.string "provider_payment_id"
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "provider_state_at"
    t.string "last_provider_event_id"
    t.integer "fee_amount", default: 0, null: false
    t.integer "gst_amount", default: 0, null: false
    t.decimal "fee_percent", precision: 6, scale: 2, default: "0.0", null: false
    t.integer "policy_version", default: 0, null: false
    t.index ["booking_quote_id"], name: "index_booking_payments_on_booking_quote_id"
    t.index ["booking_request_id", "kind"], name: "index_booking_payments_on_active_kind", unique: true, where: "((status)::text = ANY ((ARRAY['created'::character varying, 'paid'::character varying])::text[]))"
    t.index ["booking_request_id"], name: "index_booking_payments_on_booking_request_id"
    t.index ["payer_id"], name: "index_booking_payments_on_payer_id"
    t.index ["provider_order_id"], name: "index_booking_payments_on_provider_order_id", unique: true, where: "(provider_order_id IS NOT NULL)"
    t.index ["provider_payment_id"], name: "index_booking_payments_on_provider_payment_id", unique: true, where: "(provider_payment_id IS NOT NULL)"
    t.check_constraint "amount > 0", name: "booking_payments_amount_positive"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "booking_payments_currency_format"
    t.check_constraint "fee_amount >= 0 AND gst_amount >= 0", name: "booking_payments_fee_breakdown_nonnegative"
    t.check_constraint "kind::text = ANY (ARRAY['deposit'::character varying, 'balance'::character varying, 'refund'::character varying]::text[])", name: "booking_payments_kind_valid"
    t.check_constraint "provider::text = ANY (ARRAY['internal'::character varying, 'razorpay'::character varying]::text[])", name: "booking_payments_provider_valid"
    t.check_constraint "status::text = ANY (ARRAY['created'::character varying, 'paid'::character varying, 'failed'::character varying, 'refunded'::character varying]::text[])", name: "booking_payments_status_valid"
  end

  create_table "booking_quotes", id: :string, force: :cascade do |t|
    t.string "booking_request_id", null: false
    t.string "created_by_id", null: false
    t.integer "performance_fee", null: false
    t.integer "travel_fee", default: 0, null: false
    t.integer "production_fee", default: 0, null: false
    t.integer "other_fee", default: 0, null: false
    t.string "currency", null: false
    t.string "status", null: false
    t.integer "deposit_percent", default: 50, null: false
    t.datetime "valid_until"
    t.text "inclusions"
    t.text "exclusions"
    t.text "cancellation_terms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "fee_amount", default: 0, null: false
    t.integer "gst_amount", default: 0, null: false
    t.decimal "fee_percent", precision: 6, scale: 2, default: "0.0", null: false
    t.integer "policy_version", default: 0, null: false
    t.index ["booking_request_id"], name: "index_booking_quotes_on_booking_request_id"
    t.index ["created_by_id"], name: "index_booking_quotes_on_created_by_id"
    t.check_constraint "deposit_percent >= 1 AND deposit_percent <= 100", name: "booking_quotes_deposit_percent_valid"
    t.check_constraint "fee_amount >= 0 AND gst_amount >= 0", name: "booking_quotes_fee_breakdown_nonnegative"
    t.check_constraint "performance_fee >= 0 AND travel_fee >= 0 AND production_fee >= 0 AND other_fee >= 0", name: "booking_quotes_fees_nonnegative"
  end

  create_table "booking_requests", id: :string, force: :cascade do |t|
    t.string "act_id", null: false
    t.string "requester_id", null: false
    t.string "event_type", null: false
    t.string "city", null: false
    t.string "currency", null: false
    t.string "status", null: false
    t.string "event_name"
    t.string "start_time"
    t.string "venue_name"
    t.string "venue_address"
    t.string "indoor_outdoor"
    t.datetime "event_date"
    t.integer "duration_minutes"
    t.integer "audience_size"
    t.integer "budget_min"
    t.integer "budget_max"
    t.text "requirements"
    t.jsonb "production_provided", default: [], null: false
    t.boolean "travel_provided", default: false, null: false
    t.boolean "accommodation_provided", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["act_id"], name: "index_booking_requests_on_act_id"
    t.index ["requester_id"], name: "index_booking_requests_on_requester_id"
    t.check_constraint "status::text = ANY (ARRAY['requested'::character varying, 'viewed'::character varying, 'negotiating'::character varying, 'quoted'::character varying, 'accepted'::character varying, 'completed'::character varying, 'disputed'::character varying, 'declined'::character varying, 'cancelled'::character varying]::text[])", name: "booking_requests_status_valid"
  end

  create_table "career_entries", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "kind", null: false
    t.jsonb "fields", default: {}, null: false
    t.date "start_on"
    t.date "end_on"
    t.jsonb "tags", default: [], null: false
    t.integer "position", default: 0, null: false
    t.boolean "backfilled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "kind"], name: "index_career_entries_on_user_id_and_kind"
  end

  create_table "career_resources", id: :string, force: :cascade do |t|
    t.string "title", null: false
    t.string "category", null: false
    t.string "status", null: false
    t.string "url"
    t.text "description", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "conversations", id: :string, force: :cascade do |t|
    t.string "candidate_id", null: false
    t.string "employer_id", null: false
    t.string "job_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id", "employer_id", "job_id"], name: "index_conversations_on_candidate_id_and_employer_id_and_job_id", unique: true
    t.index ["candidate_id", "employer_id"], name: "index_conversations_on_pair_without_job", unique: true, where: "(job_id IS NULL)"
    t.index ["candidate_id"], name: "index_conversations_on_candidate_id"
    t.index ["employer_id"], name: "index_conversations_on_employer_id"
    t.index ["job_id"], name: "index_conversations_on_job_id"
  end

  create_table "crew_plan_roles", id: :string, force: :cascade do |t|
    t.string "crew_plan_id", null: false
    t.string "category", null: false
    t.string "role_name", null: false
    t.string "priority", null: false
    t.string "instrument"
    t.integer "count_needed", default: 1, null: false
    t.text "rationale"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["crew_plan_id"], name: "index_crew_plan_roles_on_crew_plan_id"
  end

  create_table "crew_plans", id: :string, force: :cascade do |t|
    t.string "owner_id", null: false
    t.string "title", null: false
    t.string "event_type", null: false
    t.string "city", null: false
    t.string "currency", null: false
    t.datetime "event_date"
    t.integer "audience_size"
    t.integer "budget"
    t.jsonb "genres", default: [], null: false
    t.jsonb "needs", default: [], null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_crew_plans_on_owner_id"
  end

  create_table "email_suppressions", id: :string, force: :cascade do |t|
    t.string "email", null: false
    t.string "scope", default: "none", null: false
    t.string "reason", null: false
    t.string "provider", default: "brevo", null: false
    t.integer "soft_bounce_count", default: 0, null: false
    t.string "last_event", null: false
    t.string "last_message_id"
    t.datetime "last_event_at", null: false
    t.datetime "suppressed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_email_suppressions_on_email", unique: true
    t.index ["scope"], name: "index_email_suppressions_on_scope"
  end

  create_table "email_tokens", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "purpose", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at"
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_email_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_email_tokens_on_user_id"
  end

  create_table "follows", id: :string, force: :cascade do |t|
    t.string "follower_user_id", null: false
    t.string "followable_type", null: false
    t.string "followable_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["followable_type", "followable_id"], name: "index_follows_on_followable_type_and_followable_id"
    t.index ["follower_user_id", "followable_type", "followable_id"], name: "index_follows_on_follower_and_followable", unique: true
  end

  create_table "good_job_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "description"
    t.jsonb "serialized_properties"
    t.text "on_finish"
    t.text "on_success"
    t.text "on_discard"
    t.text "callback_queue_name"
    t.integer "callback_priority"
    t.datetime "enqueued_at"
    t.datetime "discarded_at"
    t.datetime "finished_at"
    t.datetime "jobs_finished_at"
  end

  create_table "good_job_executions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id", null: false
    t.text "job_class"
    t.text "queue_name"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.text "error"
    t.integer "error_event", limit: 2
    t.text "error_backtrace", array: true
    t.uuid "process_id"
    t.interval "duration"
    t.index ["active_job_id", "created_at"], name: "index_good_job_executions_on_active_job_id_and_created_at"
    t.index ["process_id", "created_at"], name: "index_good_job_executions_on_process_id_and_created_at"
  end

  create_table "good_job_processes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "state"
    t.integer "lock_type", limit: 2
  end

  create_table "good_job_settings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "key"
    t.jsonb "value"
    t.index ["key"], name: "index_good_job_settings_on_key", unique: true
  end

  create_table "good_jobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "queue_name"
    t.integer "priority"
    t.jsonb "serialized_params"
    t.datetime "scheduled_at"
    t.datetime "performed_at"
    t.datetime "finished_at"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "active_job_id"
    t.text "concurrency_key"
    t.text "cron_key"
    t.uuid "retried_good_job_id"
    t.datetime "cron_at"
    t.uuid "batch_id"
    t.uuid "batch_callback_id"
    t.boolean "is_discrete"
    t.integer "executions_count"
    t.text "job_class"
    t.integer "error_event", limit: 2
    t.text "labels", array: true
    t.uuid "locked_by_id"
    t.datetime "locked_at"
    t.integer "lock_type", limit: 2
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["created_at"], name: "index_good_jobs_on_created_at"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_on_discarded", order: :desc, where: "((finished_at IS NOT NULL) AND (error IS NOT NULL))"
    t.index ["id"], name: "index_good_jobs_on_unfinished_or_errored", where: "((finished_at IS NULL) OR (error IS NOT NULL))"
    t.index ["job_class", "finished_at"], name: "index_good_jobs_on_discarded_job_class", where: "((finished_at IS NOT NULL) AND (error IS NOT NULL))"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_for_candidate_dequeue_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["priority", "scheduled_at", "id"], name: "index_good_jobs_on_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at", "id"], name: "index_good_jobs_on_queue_name_priority_scheduled_at_unfinished", where: "(finished_at IS NULL)"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["queue_name"], name: "index_good_jobs_on_queue_name"
    t.index ["scheduled_at", "queue_name"], name: "index_good_jobs_on_scheduled_at_and_queue_name"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
  end

  create_table "invoice_counters", id: false, force: :cascade do |t|
    t.string "series", null: false
    t.string "financial_year", null: false
    t.integer "last_value", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["series", "financial_year"], name: "index_invoice_counters_on_series_and_financial_year", unique: true
  end

  create_table "invoices", id: :string, force: :cascade do |t|
    t.string "booking_payment_id", null: false
    t.string "invoice_number", null: false
    t.string "financial_year", null: false
    t.integer "sequence_number", null: false
    t.integer "deposit_amount", null: false
    t.integer "fee_amount", null: false
    t.integer "gst_amount", null: false
    t.integer "total_amount", null: false
    t.string "currency", null: false
    t.integer "policy_version", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_payment_id"], name: "index_invoices_on_booking_payment_id", unique: true
    t.index ["financial_year", "sequence_number"], name: "index_invoices_on_financial_year_and_sequence_number", unique: true
    t.index ["invoice_number"], name: "index_invoices_on_invoice_number", unique: true
  end

  create_table "job_alert_deliveries", id: :string, force: :cascade do |t|
    t.string "job_alert_id", null: false
    t.string "job_id", null: false
    t.string "notification_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["job_alert_id", "job_id"], name: "index_job_alert_deliveries_on_job_alert_id_and_job_id", unique: true
    t.index ["job_alert_id"], name: "index_job_alert_deliveries_on_job_alert_id"
    t.index ["job_id"], name: "index_job_alert_deliveries_on_job_id"
    t.index ["notification_id"], name: "index_job_alert_deliveries_on_notification_id"
  end

  create_table "job_alerts", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "name"
    t.string "query"
    t.string "location"
    t.string "opportunity_kind"
    t.string "function_area"
    t.string "frequency"
    t.boolean "remote_only", default: false, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_run_at"
    t.datetime "next_run_at"
    t.index ["active", "next_run_at"], name: "index_job_alerts_on_active_and_next_run_at"
    t.index ["user_id"], name: "index_job_alerts_on_user_id"
  end

  create_table "jobs", id: :string, force: :cascade do |t|
    t.string "employer_id", null: false
    t.string "title", null: false
    t.string "company", null: false
    t.string "location", null: false
    t.string "kind", null: false
    t.string "genre", null: false
    t.string "salary"
    t.text "description", null: false
    t.text "requirements"
    t.jsonb "skills", default: [], null: false
    t.jsonb "languages", default: [], null: false
    t.jsonb "screening_questions", default: [], null: false
    t.string "experience_level"
    t.string "status"
    t.string "opportunity_kind"
    t.string "function_area"
    t.string "workplace"
    t.string "currency"
    t.string "compensation_period"
    t.string "duration"
    t.string "moderation_note"
    t.integer "compensation_min", default: 1
    t.integer "compensation_max", default: 1
    t.integer "slots", default: 1
    t.boolean "featured", default: false, null: false
    t.boolean "paid", default: true, null: false
    t.boolean "portfolio_required", default: false, null: false
    t.datetime "application_deadline"
    t.datetime "start_date"
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "posted_as_type"
    t.string "posted_as_id"
    t.tsvector "search_vector"
    t.text "search_text"
    t.index "((skills)::text) gin_trgm_ops", name: "index_jobs_on_skills_text_trgm", using: :gin
    t.index ["company"], name: "index_jobs_on_company", opclass: :gin_trgm_ops, using: :gin
    t.index ["description"], name: "index_jobs_on_description", opclass: :gin_trgm_ops, using: :gin
    t.index ["employer_id"], name: "index_jobs_on_employer_id"
    t.index ["posted_as_type", "posted_as_id"], name: "index_jobs_on_posted_as_type_and_posted_as_id", where: "(posted_as_id IS NOT NULL)"
    t.index ["published_at", "id"], name: "index_jobs_published_browse", order: { published_at: "DESC NULLS LAST", id: :desc }, where: "((status)::text = 'published'::text)"
    t.index ["search_text"], name: "index_jobs_on_search_text_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_vector"], name: "index_jobs_on_search_vector", using: :gin
    t.index ["status", "created_at"], name: "index_jobs_on_status_and_created_at"
    t.index ["title"], name: "index_jobs_on_title", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "legacy_function_area_backups", force: :cascade do |t|
    t.string "source_table", null: false
    t.string "record_id", null: false
    t.string "function_area", null: false
    t.datetime "record_updated_at"
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["source_table", "record_id"], name: "index_legacy_function_area_backups_on_record", unique: true
  end

  create_table "lifecycle_emails", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "key", null: false
    t.datetime "sent_at", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.index ["user_id", "key"], name: "index_lifecycle_emails_on_user_id_and_key", unique: true
  end

  create_table "messages", id: :string, force: :cascade do |t|
    t.string "conversation_id", null: false
    t.string "sender_id", null: false
    t.text "body", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "safety_flags", default: [], null: false, array: true
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_flagged_on_created_at", where: "(safety_flags <> '{}'::character varying[])"
    t.index ["sender_id"], name: "index_messages_flagged_on_sender_id", where: "(safety_flags <> '{}'::character varying[])"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "notifications", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "kind"
    t.string "title"
    t.string "link"
    t.text "body"
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["read_at"], name: "index_notifications_on_read_at_when_read", where: "(read_at IS NOT NULL)"
    t.index ["user_id", "read_at", "created_at"], name: "index_notifications_on_user_id_and_read_at_and_created_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "organization_members", id: false, force: :cascade do |t|
    t.string "organization_id", null: false
    t.string "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.index ["organization_id", "user_id"], name: "index_organization_members_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_organization_members_on_organization_id"
    t.index ["user_id"], name: "index_organization_members_on_user_id"
  end

  create_table "organizations", id: :string, force: :cascade do |t|
    t.string "owner_id", null: false
    t.string "name", null: false
    t.string "status", null: false
    t.string "org_type"
    t.string "website"
    t.string "city"
    t.string "tax_id"
    t.string "billing_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_organizations_on_owner_id"
  end

  create_table "phone_otps", id: :string, force: :cascade do |t|
    t.citext "phone", null: false
    t.string "code_digest", null: false
    t.string "pending_name"
    t.string "pending_role"
    t.integer "attempts", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "pending_consented_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_phone_otps_on_expires_at"
    t.index ["phone", "created_at"], name: "index_phone_otps_on_phone_and_created_at"
  end

  create_table "portfolio_items", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "kind"
    t.string "title"
    t.string "url"
    t.string "credited_as"
    t.string "thumbnail_url"
    t.string "waveform_url"
    t.string "visibility"
    t.text "description"
    t.jsonb "tags", default: [], null: false
    t.jsonb "genres", default: [], null: false
    t.jsonb "roles", default: [], null: false
    t.jsonb "instruments", default: [], null: false
    t.jsonb "media_metadata", default: {}, null: false
    t.integer "year", default: 0
    t.integer "sort_order", default: 0
    t.boolean "featured", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.tsvector "search_vector"
    t.text "search_text"
    t.index "((genres)::text) gin_trgm_ops", name: "index_portfolio_items_on_genres_text_trgm", using: :gin
    t.index "((roles)::text) gin_trgm_ops", name: "index_portfolio_items_on_roles_text_trgm", using: :gin
    t.index "((tags)::text) gin_trgm_ops", name: "index_portfolio_items_on_tags_text_trgm", using: :gin
    t.index ["description"], name: "index_portfolio_items_on_description", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_text"], name: "index_portfolio_items_on_search_text_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_vector"], name: "index_portfolio_items_on_search_vector", using: :gin
    t.index ["title"], name: "index_portfolio_items_on_title", opclass: :gin_trgm_ops, using: :gin
    t.index ["user_id"], name: "index_portfolio_items_on_user_id"
    t.index ["user_id"], name: "index_portfolio_items_playable_public", where: "(((visibility)::text = 'public'::text) AND ((kind)::text = ANY ((ARRAY['audio'::character varying, 'video'::character varying])::text[])) AND (btrim((COALESCE(url, ''::character varying))::text) <> ''::text))"
  end

  create_table "portfolios", id: :string, force: :cascade do |t|
    t.string "owner_type", null: false
    t.string "owner_id", null: false
    t.string "title", null: false
    t.string "purpose"
    t.string "headline"
    t.text "bio"
    t.string "city"
    t.jsonb "genres"
    t.jsonb "rates"
    t.jsonb "rules", default: {}, null: false
    t.jsonb "pinned_item_ids", default: [], null: false
    t.jsonb "excluded_item_ids", default: [], null: false
    t.jsonb "item_order", default: [], null: false
    t.string "visibility", default: "public", null: false
    t.string "slug", null: false
    t.boolean "is_default", default: false, null: false
    t.string "status", default: "active", null: false
    t.boolean "backfilled", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_portfolios_on_owner_type_and_owner_id"
    t.index ["owner_type", "owner_id"], name: "index_portfolios_one_default_per_owner", unique: true, where: "is_default"
    t.index ["slug"], name: "index_portfolios_on_slug", unique: true
  end

  create_table "post_comments", id: :string, force: :cascade do |t|
    t.string "post_id", null: false
    t.string "author_type", null: false
    t.string "author_id", null: false
    t.string "created_by_user_id", null: false
    t.text "body", null: false
    t.string "parent_id"
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_post_comments_on_created_by_user_id"
    t.index ["parent_id"], name: "index_post_comments_on_parent_id"
    t.index ["post_id", "created_at"], name: "index_post_comments_on_post_id_and_created_at"
  end

  create_table "post_reactions", id: :string, force: :cascade do |t|
    t.string "post_id", null: false
    t.string "actor_type", null: false
    t.string "actor_id", null: false
    t.string "kind", default: "applause", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_type", "actor_id"], name: "index_post_reactions_on_actor_type_and_actor_id"
    t.index ["post_id", "actor_type", "actor_id"], name: "index_post_reactions_on_post_and_actor", unique: true
  end

  create_table "posts", id: :string, force: :cascade do |t|
    t.string "author_type", null: false
    t.string "author_id", null: false
    t.string "created_by_user_id"
    t.string "kind", default: "update", null: false
    t.text "body"
    t.jsonb "media", default: [], null: false
    t.string "link_url"
    t.string "shared_portfolio_item_id"
    t.string "shared_job_id"
    t.string "reshared_post_id"
    t.string "city"
    t.string "genres", default: [], null: false, array: true
    t.string "hashtags", default: [], null: false, array: true
    t.string "visibility", default: "public", null: false
    t.string "status", default: "active", null: false
    t.integer "applause_count", default: 0, null: false
    t.integer "comment_count", default: 0, null: false
    t.integer "reshare_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "system_kind"
    t.string "system_ref"
    t.datetime "pinned_until"
    t.string "event_title"
    t.datetime "event_starts_at"
    t.string "event_venue"
    t.boolean "featured", default: false, null: false
    t.index ["author_type", "author_id", "created_at"], name: "index_posts_on_author_type_and_author_id_and_created_at"
    t.index ["created_at", "id"], name: "index_posts_on_created_at_and_id"
    t.index ["created_by_user_id"], name: "index_posts_on_created_by_user_id"
    t.index ["event_starts_at"], name: "index_posts_on_event_starts_at"
    t.index ["genres"], name: "index_posts_on_genres", using: :gin
    t.index ["hashtags"], name: "index_posts_on_hashtags", using: :gin
    t.index ["pinned_until"], name: "index_posts_on_pinned_until"
    t.index ["reshared_post_id"], name: "index_posts_on_reshared_post_id"
    t.index ["shared_job_id"], name: "index_posts_on_shared_job_id"
    t.index ["shared_portfolio_item_id"], name: "index_posts_on_shared_portfolio_item_id"
    t.index ["status"], name: "index_posts_on_status"
    t.index ["system_ref"], name: "index_posts_on_system_ref", unique: true
  end

  create_table "problem_reports", id: :string, force: :cascade do |t|
    t.string "user_id"
    t.string "email"
    t.text "description", null: false
    t.text "expected"
    t.string "page"
    t.jsonb "context", default: {}, null: false
    t.string "status", default: "new", null: false
    t.text "admin_note"
    t.bigint "screenshot_blob_id"
    t.string "handled_by_id"
    t.datetime "handled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["screenshot_blob_id"], name: "index_problem_reports_on_screenshot_blob_id"
    t.index ["status", "created_at"], name: "index_problem_reports_on_status_and_created_at"
    t.index ["user_id"], name: "index_problem_reports_on_user_id"
  end

  create_table "product_events", id: :string, force: :cascade do |t|
    t.string "user_id"
    t.string "anon_id", null: false
    t.string "name", null: false
    t.jsonb "props", default: {}, null: false
    t.string "page"
    t.string "referrer"
    t.string "city"
    t.datetime "created_at", null: false
    t.index "((props ->> 'profileId'::text))", name: "index_product_events_on_profile_view_profile_id", where: "((name)::text = 'profile_view'::text)"
    t.index ["anon_id"], name: "index_product_events_on_anon_id"
    t.index ["created_at"], name: "index_product_events_on_created_at"
    t.index ["name", "created_at"], name: "index_product_events_on_name_and_created_at"
    t.index ["user_id"], name: "index_product_events_on_user_id"
  end

  create_table "profiles", primary_key: "user_id", id: :string, force: :cascade do |t|
    t.string "headline"
    t.string "phone"
    t.string "location"
    t.string "experience"
    t.string "website"
    t.string "portfolio_url"
    t.text "bio"
    t.jsonb "skills", default: [], null: false
    t.jsonb "genres", default: [], null: false
    t.jsonb "instruments", default: [], null: false
    t.jsonb "languages", default: [], null: false
    t.jsonb "credits", default: [], null: false
    t.jsonb "open_to", default: [], null: false
    t.jsonb "roles", default: [], null: false
    t.jsonb "gear", default: [], null: false
    t.jsonb "software", default: [], null: false
    t.string "company_name"
    t.string "company_website"
    t.string "company_size"
    t.text "company_description"
    t.boolean "verified", default: false, null: false
    t.boolean "travels_nationally", default: false, null: false
    t.boolean "travels_internationally", default: false, null: false
    t.boolean "remote_recording", default: false, null: false
    t.boolean "sight_reading", default: false, null: false
    t.boolean "passport_ready", default: false, null: false
    t.integer "years_experience"
    t.integer "travel_radius_km"
    t.integer "hourly_rate"
    t.integer "session_rate"
    t.integer "show_rate"
    t.integer "tour_day_rate"
    t.integer "day_rate"
    t.string "availability"
    t.string "currency", default: "INR"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "email_notifications", default: true, null: false
    t.string "phone_e164"
    t.datetime "whatsapp_consented_at"
    t.jsonb "email_preferences", default: {"digest"=>true, "product"=>true, "requests"=>true, "lifecycle"=>true}, null: false
    t.boolean "share_verification_publicly", default: true, null: false
    t.string "photo_url"
    t.jsonb "event_types", default: [], null: false
    t.jsonb "push_preferences", default: {}, null: false
    t.tsvector "search_vector"
    t.text "search_text"
    t.integer "profile_view_count", default: 0, null: false
    t.index "((event_types)::text) gin_trgm_ops", name: "index_profiles_on_event_types_text_trgm", using: :gin
    t.index "((genres)::text) gin_trgm_ops", name: "index_profiles_on_genres_text_trgm", using: :gin
    t.index "((instruments)::text) gin_trgm_ops", name: "index_profiles_on_instruments_text_trgm", using: :gin
    t.index "((languages)::text) gin_trgm_ops", name: "index_profiles_on_languages_text_trgm", using: :gin
    t.index "((open_to)::text) gin_trgm_ops", name: "index_profiles_on_open_to_text_trgm", using: :gin
    t.index "((roles)::text) gin_trgm_ops", name: "index_profiles_on_roles_text_trgm", using: :gin
    t.index "((skills)::text) gin_trgm_ops", name: "index_profiles_on_skills_text_trgm", using: :gin
    t.index ["bio"], name: "index_profiles_on_bio", opclass: :gin_trgm_ops, using: :gin
    t.index ["headline"], name: "index_profiles_on_headline", opclass: :gin_trgm_ops, using: :gin
    t.index ["location"], name: "index_profiles_on_location_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_text"], name: "index_profiles_on_search_text_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["search_vector"], name: "index_profiles_on_search_vector", using: :gin
  end

  create_table "promo_codes", id: :string, force: :cascade do |t|
    t.citext "code", null: false
    t.string "kind", null: false
    t.integer "percent_off"
    t.integer "duration_periods"
    t.integer "trial_days"
    t.jsonb "plan_codes", default: [], null: false
    t.jsonb "intervals", default: [], null: false
    t.string "razorpay_offer_id"
    t.integer "max_redemptions"
    t.integer "redemptions_count", default: 0, null: false
    t.integer "per_user_limit", default: 1, null: false
    t.datetime "starts_at"
    t.datetime "expires_at"
    t.boolean "active", default: true, null: false
    t.string "owner_user_id"
    t.string "created_by_id"
    t.text "notes"
    t.string "batch_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_id"], name: "index_promo_codes_on_batch_id"
    t.index ["code"], name: "index_promo_codes_on_code", unique: true
    t.index ["owner_user_id"], name: "index_promo_codes_on_owner_user_id", unique: true, where: "(owner_user_id IS NOT NULL)"
    t.check_constraint "duration_periods IS NULL OR duration_periods >= 1", name: "promo_codes_duration_valid"
    t.check_constraint "kind::text = ANY (ARRAY['discount_percent'::character varying, 'extended_trial'::character varying, 'early_access'::character varying, 'referral'::character varying]::text[])", name: "promo_codes_kind_valid"
    t.check_constraint "per_user_limit >= 1", name: "promo_codes_per_user_limit_valid"
    t.check_constraint "percent_off IS NULL OR percent_off >= 1 AND percent_off <= 100", name: "promo_codes_percent_off_valid"
    t.check_constraint "trial_days IS NULL OR trial_days >= 1", name: "promo_codes_trial_days_valid"
  end

  create_table "promo_redemptions", id: :string, force: :cascade do |t|
    t.string "promo_code_id", null: false
    t.string "user_id", null: false
    t.string "subscription_id"
    t.string "kind", null: false
    t.integer "percent_off"
    t.integer "trial_days"
    t.datetime "redeemed_at", null: false
    t.datetime "referrer_rewarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["promo_code_id", "user_id"], name: "index_promo_redemptions_on_code_and_user"
    t.index ["subscription_id"], name: "index_promo_redemptions_on_subscription_id"
    t.index ["user_id"], name: "index_promo_redemptions_on_user_id"
  end

  create_table "push_subscriptions", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.text "endpoint", null: false
    t.string "endpoint_digest", null: false
    t.text "p256dh", null: false
    t.text "auth", null: false
    t.string "user_agent_summary"
    t.datetime "last_success_at"
    t.datetime "last_failure_at"
    t.integer "failure_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint_digest"], name: "index_push_subscriptions_on_endpoint_digest", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "recent_activities", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "kind", null: false
    t.string "query"
    t.string "entity_id"
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_recent_activities_on_user_id"
  end

  create_table "refund_records", id: :string, force: :cascade do |t|
    t.string "booking_request_id", null: false
    t.string "booking_payment_id"
    t.string "requested_by_id", null: false
    t.string "decided_by_id"
    t.integer "amount", null: false
    t.string "currency", null: false
    t.integer "refund_percent", null: false
    t.string "reason", null: false
    t.string "status", default: "pending_manual", null: false
    t.integer "policy_version", default: 0, null: false
    t.text "note"
    t.datetime "decided_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["booking_payment_id"], name: "index_refund_records_on_booking_payment_id"
    t.index ["booking_request_id"], name: "index_refund_records_on_booking_request_id"
    t.index ["status"], name: "index_refund_records_on_status"
    t.check_constraint "amount >= 0", name: "refund_records_amount_nonnegative"
    t.check_constraint "refund_percent >= 0 AND refund_percent <= 100", name: "refund_records_percent_valid"
    t.check_constraint "status::text = ANY (ARRAY['pending_manual'::character varying, 'done'::character varying, 'not_applicable'::character varying]::text[])", name: "refund_records_status_valid"
  end

  create_table "reports", id: :string, force: :cascade do |t|
    t.string "reporter_id"
    t.string "entity_type", null: false
    t.string "entity_id", null: false
    t.string "reason", null: false
    t.string "status", null: false
    t.text "details"
    t.string "resolved_by_id"
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "action_taken"
    t.text "resolution_note"
    t.index ["entity_type", "entity_id"], name: "index_reports_on_entity_type_and_entity_id"
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["resolved_by_id"], name: "index_reports_on_resolved_by_id"
  end

  create_table "request_metric_minutes", id: false, force: :cascade do |t|
    t.datetime "minute", null: false
    t.integer "requests", default: 0, null: false
    t.integer "server_errors", default: 0, null: false
    t.integer "latency_histogram", default: [], null: false, array: true
    t.index ["minute"], name: "index_request_metric_minutes_on_minute", unique: true
  end

  create_table "resumes", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "title", null: false
    t.string "target_role"
    t.string "headline"
    t.text "summary"
    t.jsonb "rules", default: {}, null: false
    t.jsonb "pinned_entry_ids", default: [], null: false
    t.jsonb "excluded_entry_ids", default: [], null: false
    t.jsonb "entry_order", default: [], null: false
    t.jsonb "section_order", default: [], null: false
    t.string "upload_id"
    t.boolean "is_default", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["upload_id"], name: "index_resumes_on_upload_id"
    t.index ["user_id"], name: "index_resumes_on_user_id"
    t.index ["user_id"], name: "index_resumes_one_default_per_user", unique: true, where: "is_default"
  end

  create_table "review_prompts", id: :string, force: :cascade do |t|
    t.string "source_type", null: false
    t.string "source_id", null: false
    t.string "user_id", null: false
    t.string "counterpart_user_id", null: false
    t.string "counterpart_name", null: false
    t.datetime "notified_at"
    t.datetime "reminded_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_type", "source_id", "user_id"], name: "index_review_prompts_on_source_and_user", unique: true
    t.index ["user_id"], name: "index_review_prompts_on_user_id"
  end

  create_table "reviews", id: :string, force: :cascade do |t|
    t.string "author_id", null: false
    t.string "employer_id", null: false
    t.integer "rating", null: false
    t.string "title"
    t.string "status", default: "pending", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_reviews_on_author_id"
    t.index ["employer_id"], name: "index_reviews_on_employer_id"
  end

  create_table "saved_jobs", id: false, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "job_id", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_saved_jobs_on_job_id"
    t.index ["user_id", "job_id"], name: "index_saved_jobs_on_user_id_and_job_id", unique: true
    t.index ["user_id"], name: "index_saved_jobs_on_user_id"
  end

  create_table "sessions", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_seen_at"
    t.datetime "absolute_expires_at"
    t.string "client_fingerprint"
    t.datetime "flagged_at"
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "showcase_suggestions", id: :string, force: :cascade do |t|
    t.string "owner_type", null: false
    t.string "owner_id", null: false
    t.string "target_type", null: false
    t.string "target_id", null: false
    t.string "subject_type", null: false
    t.string "subject_id", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.string "reason"
    t.string "status", default: "pending", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "status"], name: "idx_on_owner_type_owner_id_status_473d48edb0"
    t.index ["subject_type", "subject_id"], name: "index_showcase_suggestions_on_subject_type_and_subject_id"
    t.index ["target_type", "target_id", "subject_type", "subject_id", "kind"], name: "index_showcase_suggestions_uniqueness", unique: true
  end

  create_table "sign_in_codes", id: :string, force: :cascade do |t|
    t.citext "email", null: false
    t.string "code_digest", null: false
    t.string "pending_name"
    t.string "pending_role"
    t.integer "attempts", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "pending_consented_at"
    t.index ["email", "created_at"], name: "index_sign_in_codes_on_email_and_created_at"
    t.index ["expires_at"], name: "index_sign_in_codes_on_expires_at"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.binary "payload", null: false
    t.datetime "created_at", null: false
    t.bigint "channel_hash", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.binary "key", null: false
    t.binary "value", null: false
    t.datetime "created_at", null: false
    t.bigint "key_hash", null: false
    t.integer "byte_size", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "subscriptions", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "plan_code", null: false
    t.string "provider", null: false
    t.string "status", null: false
    t.string "provider_subscription_id"
    t.datetime "trial_started_at"
    t.datetime "trial_ends_at"
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "provider_state_at"
    t.string "last_provider_event_id"
    t.boolean "early_access", default: false, null: false
    t.string "interval", default: "monthly", null: false
    t.string "promo_code_id"
    t.integer "discount_percent"
    t.integer "discount_periods"
    t.integer "discount_periods_used", default: 0, null: false
    t.index ["promo_code_id"], name: "index_subscriptions_on_promo_code_id"
    t.index ["provider_subscription_id"], name: "index_subscriptions_on_provider_subscription_id", unique: true, where: "(provider_subscription_id IS NOT NULL)"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.check_constraint "\"interval\"::text = ANY (ARRAY['monthly'::character varying, 'annual'::character varying]::text[])", name: "subscriptions_interval_valid"
    t.check_constraint "provider::text = ANY (ARRAY['internal'::character varying, 'razorpay'::character varying]::text[])", name: "subscriptions_provider_valid"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'trialing'::character varying::text, 'active'::character varying::text, 'past_due'::character varying::text, 'cancelled'::character varying::text, 'early_access'::character varying::text])", name: "subscriptions_status_valid"
  end

  create_table "talent_folder_members", id: false, force: :cascade do |t|
    t.string "talent_folder_id", null: false
    t.string "candidate_id", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.index ["candidate_id"], name: "index_talent_folder_members_on_candidate_id"
    t.index ["talent_folder_id", "candidate_id"], name: "idx_talent_folder_member_unique", unique: true
    t.index ["talent_folder_id"], name: "index_talent_folder_members_on_talent_folder_id"
  end

  create_table "talent_folders", id: :string, force: :cascade do |t|
    t.string "owner_id", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_talent_folders_on_owner_id"
  end

  create_table "talent_shortlists", id: false, force: :cascade do |t|
    t.string "employer_id", null: false
    t.string "candidate_id", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.index ["candidate_id"], name: "index_talent_shortlists_on_candidate_id"
    t.index ["employer_id", "candidate_id"], name: "index_talent_shortlists_on_employer_id_and_candidate_id", unique: true
    t.index ["employer_id"], name: "index_talent_shortlists_on_employer_id"
  end

  create_table "tax_invoices", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "subscription_id"
    t.string "billing_profile_id"
    t.string "invoice_number", null: false
    t.string "financial_year", null: false
    t.integer "sequence_number", null: false
    t.string "document_type", null: false
    t.datetime "issued_at", null: false
    t.string "provider_payment_id", null: false
    t.string "provider_invoice_id"
    t.string "currency", default: "INR", null: false
    t.jsonb "seller", default: {}, null: false
    t.jsonb "buyer", default: {}, null: false
    t.jsonb "line_items", default: [], null: false
    t.string "sac_code"
    t.string "place_of_supply_code"
    t.bigint "taxable_paise", null: false
    t.bigint "cgst_paise", default: 0, null: false
    t.bigint "sgst_paise", default: 0, null: false
    t.bigint "igst_paise", default: 0, null: false
    t.bigint "total_paise", null: false
    t.string "refund_status"
    t.string "refund_reference"
    t.datetime "refunded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["billing_profile_id"], name: "index_tax_invoices_on_billing_profile_id"
    t.index ["financial_year", "sequence_number"], name: "index_tax_invoices_on_financial_year_and_sequence_number", unique: true
    t.index ["invoice_number"], name: "index_tax_invoices_on_invoice_number", unique: true
    t.index ["issued_at"], name: "index_tax_invoices_on_issued_at"
    t.index ["provider_payment_id"], name: "index_tax_invoices_on_provider_payment_id", unique: true
    t.index ["subscription_id"], name: "index_tax_invoices_on_subscription_id"
    t.index ["user_id"], name: "index_tax_invoices_on_user_id"
    t.check_constraint "(taxable_paise + cgst_paise + sgst_paise + igst_paise) = total_paise", name: "tax_invoices_totals_add_up"
    t.check_constraint "document_type::text = ANY (ARRAY['tax_invoice'::character varying, 'bill_of_supply'::character varying]::text[])", name: "tax_invoices_document_type_valid"
  end

  create_table "uploads", id: :string, force: :cascade do |t|
    t.string "user_id"
    t.string "storage", null: false
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size", null: false
    t.string "status", default: "pending", null: false
    t.string "public_url"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variants", default: {}, null: false
    t.index ["public_url"], name: "index_uploads_on_public_url"
    t.index ["status", "created_at"], name: "index_uploads_on_status_and_created_at"
    t.index ["storage", "key"], name: "index_uploads_on_storage_and_key", unique: true
    t.index ["user_id", "status"], name: "index_uploads_on_user_id_and_status"
  end

  create_table "urgent_request_notifications", id: :string, force: :cascade do |t|
    t.string "urgent_request_id", null: false
    t.string "user_id", null: false
    t.string "channel", null: false
    t.string "notified_by_admin_id"
    t.datetime "created_at", null: false
    t.jsonb "reasons", default: [], null: false
    t.index ["urgent_request_id", "user_id", "channel"], name: "idx_urgent_notif_unique", unique: true
    t.index ["user_id"], name: "index_urgent_request_notifications_on_user_id"
  end

  create_table "urgent_request_responses", id: false, force: :cascade do |t|
    t.string "urgent_request_id", null: false
    t.string "user_id", null: false
    t.text "message"
    t.integer "rate"
    t.string "status", default: "available", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["urgent_request_id", "user_id"], name: "idx_urgent_response_unique", unique: true
    t.index ["urgent_request_id"], name: "index_urgent_request_responses_on_urgent_request_id"
    t.index ["user_id"], name: "index_urgent_request_responses_on_user_id"
  end

  create_table "urgent_requests", id: :string, force: :cascade do |t|
    t.string "requester_id", null: false
    t.string "title", null: false
    t.string "role_name", null: false
    t.string "city", null: false
    t.string "currency", null: false
    t.string "status", null: false
    t.string "instrument"
    t.string "genre"
    t.datetime "start_at"
    t.datetime "end_at"
    t.integer "budget_min"
    t.integer "budget_max"
    t.text "requirements"
    t.boolean "travel_covered", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "notified_count", default: 0, null: false
    t.datetime "first_notified_at"
    t.datetime "last_notified_at"
    t.string "filled_by_id"
    t.text "founder_notes"
    t.datetime "expires_at"
    t.datetime "expiry_warned_at"
    t.string "match_status", default: "pending", null: false
    t.datetime "matched_at"
    t.index ["expires_at"], name: "index_urgent_requests_on_expires_at"
    t.index ["filled_by_id"], name: "index_urgent_requests_on_filled_by_id_filled", where: "((status)::text = 'filled'::text)"
    t.index ["requester_id"], name: "index_urgent_requests_on_requester_id"
    t.index ["start_at"], name: "index_urgent_requests_on_start_at"
    t.index ["status"], name: "index_urgent_requests_on_status"
  end

  create_table "user_blocks", id: :string, force: :cascade do |t|
    t.string "blocker_id", null: false
    t.string "blocked_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_user_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_user_blocks_on_blocker_id_and_blocked_id", unique: true
  end

  create_table "users", id: :string, force: :cascade do |t|
    t.string "name", null: false
    t.citext "email", null: false
    t.string "role", null: false
    t.string "password_digest", null: false
    t.string "status", default: "active", null: false
    t.boolean "profile_complete", default: false, null: false
    t.boolean "email_verified", default: false, null: false
    t.datetime "last_login_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "synthetic_batch"
    t.datetime "consented_at"
    t.string "vouched_by_id"
    t.citext "phone"
    t.datetime "phone_verified_at"
    t.datetime "password_set_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["name"], name: "index_users_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["phone"], name: "index_users_on_phone", unique: true, where: "(phone IS NOT NULL)"
    t.index ["synthetic_batch"], name: "index_users_on_synthetic_batch", where: "(synthetic_batch IS NOT NULL)"
    t.index ["vouched_by_id"], name: "index_users_on_vouched_by_id"
  end

  create_table "verification_requests", id: :string, force: :cascade do |t|
    t.string "user_id", null: false
    t.string "kind", null: false
    t.string "evidence_url"
    t.string "status", default: "pending", null: false
    t.text "note"
    t.string "reviewed_by_id"
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "checks", default: [], null: false
    t.integer "evidence_score"
    t.jsonb "evidence_breakdown", default: {}, null: false
    t.jsonb "flags", default: [], null: false
    t.string "auto_decision"
    t.boolean "audit_sample", default: false, null: false
    t.text "summary"
    t.index ["audit_sample"], name: "idx_verification_requests_audit_sample", where: "audit_sample"
    t.index ["reviewed_by_id"], name: "index_verification_requests_on_reviewed_by_id"
    t.index ["user_id"], name: "index_verification_requests_on_user_id"
    t.check_constraint "auto_decision::text = ANY (ARRAY['auto_approved'::character varying, 'needs_more_proof'::character varying]::text[])", name: "verification_requests_auto_decision_valid"
  end

  create_table "vouches", id: :string, force: :cascade do |t|
    t.string "voucher_id", null: false
    t.citext "vouchee_email", null: false
    t.string "vouchee_id"
    t.string "token", null: false
    t.string "status", default: "invited", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_vouches_on_token", unique: true
    t.index ["vouchee_id"], name: "index_vouches_on_vouchee_id"
    t.index ["voucher_id", "vouchee_email"], name: "idx_vouches_voucher_and_email", unique: true
    t.check_constraint "status::text = ANY (ARRAY['invited'::character varying, 'joined'::character varying, 'verified'::character varying]::text[])", name: "vouches_status_valid"
  end

  add_foreign_key "act_invites", "acts", on_delete: :cascade
  add_foreign_key "act_invites", "users", column: "invitee_user_id", on_delete: :cascade
  add_foreign_key "act_invites", "users", column: "inviter_id", on_delete: :cascade
  add_foreign_key "act_members", "acts"
  add_foreign_key "act_members", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "acts", "users", column: "owner_id"
  add_foreign_key "application_events", "applications"
  add_foreign_key "application_events", "users", column: "actor_id"
  add_foreign_key "applications", "jobs"
  add_foreign_key "applications", "portfolios", on_delete: :nullify
  add_foreign_key "applications", "resumes", on_delete: :nullify
  add_foreign_key "applications", "users", column: "candidate_id"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "availability_windows", "users"
  add_foreign_key "badges", "users"
  add_foreign_key "band_project_roles", "band_projects"
  add_foreign_key "band_project_roles", "jobs", column: "opportunity_id"
  add_foreign_key "band_projects", "users", column: "owner_id"
  add_foreign_key "billing_attempts", "users"
  add_foreign_key "billing_credits", "promo_redemptions", on_delete: :nullify
  add_foreign_key "billing_credits", "users", on_delete: :cascade
  add_foreign_key "billing_events", "users"
  add_foreign_key "billing_profiles", "users"
  add_foreign_key "billing_reminders", "subscriptions", on_delete: :cascade
  add_foreign_key "booking_payments", "booking_quotes"
  add_foreign_key "booking_payments", "booking_requests"
  add_foreign_key "booking_payments", "users", column: "payer_id"
  add_foreign_key "booking_quotes", "booking_requests"
  add_foreign_key "booking_quotes", "users", column: "created_by_id"
  add_foreign_key "booking_requests", "acts"
  add_foreign_key "booking_requests", "users", column: "requester_id"
  add_foreign_key "career_entries", "users"
  add_foreign_key "conversations", "jobs"
  add_foreign_key "conversations", "users", column: "candidate_id"
  add_foreign_key "conversations", "users", column: "employer_id"
  add_foreign_key "crew_plan_roles", "crew_plans"
  add_foreign_key "crew_plans", "users", column: "owner_id"
  add_foreign_key "email_tokens", "users"
  add_foreign_key "follows", "users", column: "follower_user_id"
  add_foreign_key "invoices", "booking_payments"
  add_foreign_key "job_alert_deliveries", "job_alerts"
  add_foreign_key "job_alert_deliveries", "jobs"
  add_foreign_key "job_alert_deliveries", "notifications", on_delete: :nullify
  add_foreign_key "job_alerts", "users"
  add_foreign_key "jobs", "users", column: "employer_id"
  add_foreign_key "lifecycle_emails", "users", on_delete: :cascade
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "organization_members", "organizations"
  add_foreign_key "organization_members", "users"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "portfolio_items", "users"
  add_foreign_key "post_comments", "post_comments", column: "parent_id", on_delete: :cascade
  add_foreign_key "post_comments", "posts", on_delete: :cascade
  add_foreign_key "post_comments", "users", column: "created_by_user_id"
  add_foreign_key "post_reactions", "posts", on_delete: :cascade
  add_foreign_key "posts", "jobs", column: "shared_job_id", on_delete: :nullify
  add_foreign_key "posts", "portfolio_items", column: "shared_portfolio_item_id", on_delete: :nullify
  add_foreign_key "posts", "posts", column: "reshared_post_id", on_delete: :nullify
  add_foreign_key "posts", "users", column: "created_by_user_id"
  add_foreign_key "problem_reports", "users", column: "handled_by_id", on_delete: :nullify
  add_foreign_key "problem_reports", "users", on_delete: :cascade
  add_foreign_key "product_events", "users", on_delete: :nullify
  add_foreign_key "profiles", "users"
  add_foreign_key "promo_codes", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "promo_codes", "users", column: "owner_user_id", on_delete: :nullify
  add_foreign_key "promo_redemptions", "promo_codes", on_delete: :cascade
  add_foreign_key "promo_redemptions", "subscriptions", on_delete: :nullify
  add_foreign_key "promo_redemptions", "users", on_delete: :cascade
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "recent_activities", "users"
  add_foreign_key "refund_records", "booking_payments", on_delete: :nullify
  add_foreign_key "refund_records", "booking_requests"
  add_foreign_key "refund_records", "users", column: "decided_by_id", on_delete: :nullify
  add_foreign_key "refund_records", "users", column: "requested_by_id"
  add_foreign_key "reports", "users", column: "reporter_id"
  add_foreign_key "reports", "users", column: "resolved_by_id"
  add_foreign_key "resumes", "uploads", on_delete: :nullify
  add_foreign_key "resumes", "users"
  add_foreign_key "review_prompts", "users"
  add_foreign_key "review_prompts", "users", column: "counterpart_user_id"
  add_foreign_key "reviews", "users", column: "author_id"
  add_foreign_key "reviews", "users", column: "employer_id"
  add_foreign_key "saved_jobs", "jobs"
  add_foreign_key "saved_jobs", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "promo_codes", on_delete: :nullify
  add_foreign_key "subscriptions", "users"
  add_foreign_key "talent_folder_members", "talent_folders"
  add_foreign_key "talent_folder_members", "users", column: "candidate_id"
  add_foreign_key "talent_folders", "users", column: "owner_id"
  add_foreign_key "talent_shortlists", "users", column: "candidate_id"
  add_foreign_key "talent_shortlists", "users", column: "employer_id"
  add_foreign_key "tax_invoices", "billing_profiles", on_delete: :nullify
  add_foreign_key "tax_invoices", "subscriptions", on_delete: :nullify
  add_foreign_key "tax_invoices", "users"
  add_foreign_key "uploads", "users", on_delete: :nullify
  add_foreign_key "urgent_request_notifications", "urgent_requests"
  add_foreign_key "urgent_request_notifications", "users"
  add_foreign_key "urgent_request_notifications", "users", column: "notified_by_admin_id"
  add_foreign_key "urgent_request_responses", "urgent_requests"
  add_foreign_key "urgent_request_responses", "users"
  add_foreign_key "urgent_requests", "users", column: "filled_by_id"
  add_foreign_key "urgent_requests", "users", column: "requester_id"
  add_foreign_key "user_blocks", "users", column: "blocked_id", on_delete: :cascade
  add_foreign_key "user_blocks", "users", column: "blocker_id", on_delete: :cascade
  add_foreign_key "users", "users", column: "vouched_by_id", on_delete: :nullify
  add_foreign_key "verification_requests", "users"
  add_foreign_key "verification_requests", "users", column: "reviewed_by_id"
  add_foreign_key "vouches", "users", column: "vouchee_id", on_delete: :nullify
  add_foreign_key "vouches", "users", column: "voucher_id"
end
