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

ActiveRecord::Schema[7.2].define(version: 2026_09_26_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

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
    t.index ["name"], name: "index_acts_on_name", opclass: :gin_trgm_ops, using: :gin
    t.index ["owner_id"], name: "index_acts_on_owner_id"
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
    t.index ["candidate_id"], name: "index_applications_on_candidate_id"
    t.index ["job_id", "candidate_id"], name: "index_applications_on_job_id_and_candidate_id", unique: true
    t.index ["job_id"], name: "index_applications_on_job_id"
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
    t.index ["booking_quote_id"], name: "index_booking_payments_on_booking_quote_id"
    t.index ["booking_request_id", "kind"], name: "index_booking_payments_on_active_kind", unique: true, where: "((status)::text = ANY ((ARRAY['created'::character varying, 'paid'::character varying])::text[]))"
    t.index ["booking_request_id"], name: "index_booking_payments_on_booking_request_id"
    t.index ["payer_id"], name: "index_booking_payments_on_payer_id"
    t.index ["provider_order_id"], name: "index_booking_payments_on_provider_order_id", unique: true, where: "(provider_order_id IS NOT NULL)"
    t.index ["provider_payment_id"], name: "index_booking_payments_on_provider_payment_id", unique: true, where: "(provider_payment_id IS NOT NULL)"
    t.check_constraint "amount > 0", name: "booking_payments_amount_positive"
    t.check_constraint "currency::text ~ '^[A-Z]{3}$'::text", name: "booking_payments_currency_format"
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
    t.index ["booking_request_id"], name: "index_booking_quotes_on_booking_request_id"
    t.index ["created_by_id"], name: "index_booking_quotes_on_created_by_id"
    t.check_constraint "deposit_percent >= 1 AND deposit_percent <= 100", name: "booking_quotes_deposit_percent_valid"
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
    t.index ["active_job_id", "created_at"], name: "index_good_jobs_on_active_job_id_and_created_at"
    t.index ["batch_callback_id"], name: "index_good_jobs_on_batch_callback_id", where: "(batch_callback_id IS NOT NULL)"
    t.index ["batch_id"], name: "index_good_jobs_on_batch_id", where: "(batch_id IS NOT NULL)"
    t.index ["concurrency_key", "created_at"], name: "index_good_jobs_on_concurrency_key_and_created_at"
    t.index ["concurrency_key"], name: "index_good_jobs_on_concurrency_key_when_unfinished", where: "(finished_at IS NULL)"
    t.index ["cron_key", "created_at"], name: "index_good_jobs_on_cron_key_and_created_at_cond", where: "(cron_key IS NOT NULL)"
    t.index ["cron_key", "cron_at"], name: "index_good_jobs_on_cron_key_and_cron_at_cond", unique: true, where: "(cron_key IS NOT NULL)"
    t.index ["finished_at"], name: "index_good_jobs_jobs_on_finished_at_only", where: "(finished_at IS NOT NULL)"
    t.index ["job_class"], name: "index_good_jobs_on_job_class"
    t.index ["labels"], name: "index_good_jobs_on_labels", where: "(labels IS NOT NULL)", using: :gin
    t.index ["locked_by_id"], name: "index_good_jobs_on_locked_by_id", where: "(locked_by_id IS NOT NULL)"
    t.index ["priority", "created_at"], name: "index_good_job_jobs_for_candidate_lookup", where: "(finished_at IS NULL)"
    t.index ["priority", "created_at"], name: "index_good_jobs_jobs_on_priority_created_at_when_unfinished", order: { priority: "DESC NULLS LAST" }, where: "(finished_at IS NULL)"
    t.index ["priority", "scheduled_at"], name: "index_good_jobs_on_priority_scheduled_at_unfinished_unlocked", where: "((finished_at IS NULL) AND (locked_by_id IS NULL))"
    t.index ["queue_name", "scheduled_at"], name: "index_good_jobs_on_queue_name_and_scheduled_at", where: "(finished_at IS NULL)"
    t.index ["scheduled_at"], name: "index_good_jobs_on_scheduled_at", where: "(finished_at IS NULL)"
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
    t.index ["company"], name: "index_jobs_on_company", opclass: :gin_trgm_ops, using: :gin
    t.index ["employer_id"], name: "index_jobs_on_employer_id"
    t.index ["status", "created_at"], name: "index_jobs_on_status_and_created_at"
    t.index ["title"], name: "index_jobs_on_title", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "messages", id: :string, force: :cascade do |t|
    t.string "conversation_id", null: false
    t.string "sender_id", null: false
    t.text "body", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
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
    t.index ["user_id"], name: "index_portfolio_items_on_user_id"
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
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["resolved_by_id"], name: "index_reports_on_resolved_by_id"
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
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
    t.index ["provider_subscription_id"], name: "index_subscriptions_on_provider_subscription_id", unique: true, where: "(provider_subscription_id IS NOT NULL)"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.check_constraint "provider::text = ANY (ARRAY['internal'::character varying, 'razorpay'::character varying]::text[])", name: "subscriptions_provider_valid"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'trialing'::character varying, 'active'::character varying, 'past_due'::character varying, 'cancelled'::character varying]::text[])", name: "subscriptions_status_valid"
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
    t.index ["requester_id"], name: "index_urgent_requests_on_requester_id"
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["synthetic_batch"], name: "index_users_on_synthetic_batch", where: "(synthetic_batch IS NOT NULL)"
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
    t.index ["reviewed_by_id"], name: "index_verification_requests_on_reviewed_by_id"
    t.index ["user_id"], name: "index_verification_requests_on_user_id"
  end

  add_foreign_key "act_members", "acts"
  add_foreign_key "act_members", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "acts", "users", column: "owner_id"
  add_foreign_key "application_events", "applications"
  add_foreign_key "application_events", "users", column: "actor_id"
  add_foreign_key "applications", "jobs"
  add_foreign_key "applications", "users", column: "candidate_id"
  add_foreign_key "audit_logs", "users", column: "actor_id"
  add_foreign_key "availability_windows", "users"
  add_foreign_key "band_project_roles", "band_projects"
  add_foreign_key "band_project_roles", "jobs", column: "opportunity_id"
  add_foreign_key "band_projects", "users", column: "owner_id"
  add_foreign_key "billing_attempts", "users"
  add_foreign_key "billing_events", "users"
  add_foreign_key "booking_payments", "booking_quotes"
  add_foreign_key "booking_payments", "booking_requests"
  add_foreign_key "booking_payments", "users", column: "payer_id"
  add_foreign_key "booking_quotes", "booking_requests"
  add_foreign_key "booking_quotes", "users", column: "created_by_id"
  add_foreign_key "booking_requests", "acts"
  add_foreign_key "booking_requests", "users", column: "requester_id"
  add_foreign_key "conversations", "jobs"
  add_foreign_key "conversations", "users", column: "candidate_id"
  add_foreign_key "conversations", "users", column: "employer_id"
  add_foreign_key "crew_plan_roles", "crew_plans"
  add_foreign_key "crew_plans", "users", column: "owner_id"
  add_foreign_key "email_tokens", "users"
  add_foreign_key "job_alert_deliveries", "job_alerts"
  add_foreign_key "job_alert_deliveries", "jobs"
  add_foreign_key "job_alert_deliveries", "notifications", on_delete: :nullify
  add_foreign_key "job_alerts", "users"
  add_foreign_key "jobs", "users", column: "employer_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "organization_members", "organizations"
  add_foreign_key "organization_members", "users"
  add_foreign_key "organizations", "users", column: "owner_id"
  add_foreign_key "portfolio_items", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "recent_activities", "users"
  add_foreign_key "reports", "users", column: "reporter_id"
  add_foreign_key "reports", "users", column: "resolved_by_id"
  add_foreign_key "reviews", "users", column: "author_id"
  add_foreign_key "reviews", "users", column: "employer_id"
  add_foreign_key "saved_jobs", "jobs"
  add_foreign_key "saved_jobs", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "talent_folder_members", "talent_folders"
  add_foreign_key "talent_folder_members", "users", column: "candidate_id"
  add_foreign_key "talent_folders", "users", column: "owner_id"
  add_foreign_key "talent_shortlists", "users", column: "candidate_id"
  add_foreign_key "talent_shortlists", "users", column: "employer_id"
  add_foreign_key "urgent_request_responses", "urgent_requests"
  add_foreign_key "urgent_request_responses", "users"
  add_foreign_key "urgent_requests", "users", column: "requester_id"
  add_foreign_key "verification_requests", "users"
  add_foreign_key "verification_requests", "users", column: "reviewed_by_id"
end
