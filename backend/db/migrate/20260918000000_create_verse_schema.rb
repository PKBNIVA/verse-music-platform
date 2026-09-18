class CreateVerseSchema < ActiveRecord::Migration[7.2]
  def change
    enable_extension "pgcrypto"
    enable_extension "citext"

    create_table :users, id: :string do |t|
      t.string :name, null: false
      t.citext :email, null: false
      t.string :role, null: false
      t.string :password_digest, null: false
      t.string :status, null: false, default: "active"
      t.boolean :profile_complete, null: false, default: false
      t.boolean :email_verified, null: false, default: false
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :users, :email, unique: true

    create_table :profiles, id: false do |t|
      t.string :user_id, null: false, primary_key: true
      t.string :headline, :phone, :location, :experience, :website, :portfolio_url
      t.text :bio
      t.jsonb :skills, :genres, :instruments, :languages, :credits, :open_to, :roles, :gear, :software, default: [], null: false
      t.string :company_name, :company_website, :company_size
      t.text :company_description
      t.boolean :verified, :travels_nationally, :travels_internationally, :remote_recording, :sight_reading, :passport_ready, default: false, null: false
      t.integer :years_experience, :travel_radius_km, :hourly_rate, :session_rate, :show_rate, :tour_day_rate, :day_rate
      t.string :availability
      t.string :currency, default: "INR"
      t.timestamps
    end
    add_foreign_key :profiles, :users

    create_table :sessions, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :sessions, :token_digest, unique: true

    create_table :jobs, id: :string do |t|
      t.references :employer, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :title, :company, :location, :kind, :genre, null: false
      t.string :salary
      t.text :description, null: false
      t.text :requirements
      t.jsonb :skills, :languages, :screening_questions, default: [], null: false
      t.string :experience_level, :status, :opportunity_kind, :function_area, :workplace, :currency, :compensation_period, :duration, :moderation_note
      t.integer :compensation_min, :compensation_max, :slots, default: 1
      t.boolean :featured, default: false, null: false
      t.boolean :paid, default: true, null: false
      t.boolean :portfolio_required, default: false, null: false
      t.datetime :application_deadline, :start_date, :published_at
      t.timestamps
    end
    add_index :jobs, %i[status created_at]

    create_table :applications, id: :string do |t|
      t.references :job, type: :string, null: false, foreign_key: true
      t.references :candidate, type: :string, null: false, foreign_key: { to_table: :users }
      t.text :cover_letter, :recruiter_note
      t.string :status, null: false, default: "Applied"
      t.datetime :interview_date
      t.integer :recruiter_rating
      t.jsonb :screening_answers, default: [], null: false
      t.timestamps
    end
    add_index :applications, %i[job_id candidate_id], unique: true

    create_table :saved_jobs, id: false do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.references :job, type: :string, null: false, foreign_key: true
      t.datetime :created_at, null: false
    end
    add_index :saved_jobs, %i[user_id job_id], unique: true

    create_table :job_alerts, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :name, :query, :location, :opportunity_kind, :function_area, :frequency
      t.boolean :remote_only, default: false, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    create_table :portfolio_items, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :kind, :title, :url, :credited_as, :thumbnail_url, :waveform_url, :visibility
      t.text :description
      t.jsonb :tags, :genres, :roles, :instruments, default: [], null: false
      t.jsonb :media_metadata, default: {}, null: false
      t.integer :year, :sort_order, default: 0
      t.boolean :featured, default: false, null: false
      t.timestamps
    end

    create_table :notifications, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :kind, :title, :link
      t.text :body
      t.datetime :read_at
      t.timestamps
    end

    create_table :reports, id: :string do |t|
      t.references :reporter, type: :string, foreign_key: { to_table: :users }
      t.string :entity_type, :entity_id, :reason, :status, null: false
      t.text :details
      t.references :resolved_by, type: :string, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.timestamps
    end

    create_table :reviews, id: :string do |t|
      t.references :author, type: :string, null: false, foreign_key: { to_table: :users }
      t.references :employer, type: :string, null: false, foreign_key: { to_table: :users }
      t.integer :rating, null: false
      t.string :title
      t.string :status, default: "pending", null: false
      t.text :body, null: false
      t.timestamps
    end

    create_table :verification_requests, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :kind, :evidence_url, :status, null: false, default: "pending"
      t.text :note
      t.references :reviewed_by, type: :string, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.timestamps
    end

    create_table :email_tokens, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :purpose, :token_digest, null: false
      t.datetime :expires_at, :used_at
      t.timestamps
    end
    add_index :email_tokens, :token_digest, unique: true

    create_table :audit_logs, id: :string do |t|
      t.references :actor, type: :string, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :entity_type, :entity_id
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    create_table :career_resources, id: :string do |t|
      t.string :title, :category, :status, null: false
      t.string :url
      t.text :description, null: false
      t.timestamps
    end

    create_table :subscriptions, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :plan_code, :provider, :provider_subscription_id, :status, null: false
      t.datetime :trial_started_at, :trial_ends_at, :current_period_start, :current_period_end
      t.boolean :cancel_at_period_end, default: false, null: false
      t.timestamps
    end

    create_table :availability_windows, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.datetime :start_at, :end_at, null: false
      t.string :status, null: false, default: "available"
      t.string :city
      t.text :note
      t.timestamps
    end

    create_table :recent_activities, id: :string do |t|
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :query, :entity_id, :label
      t.timestamps
    end

    create_table :talent_shortlists, id: false do |t|
      t.references :employer, type: :string, null: false, foreign_key: { to_table: :users }
      t.references :candidate, type: :string, null: false, foreign_key: { to_table: :users }
      t.text :note
      t.datetime :created_at, null: false
    end
    add_index :talent_shortlists, %i[employer_id candidate_id], unique: true

    create_table :conversations, id: :string do |t|
      t.references :candidate, type: :string, null: false, foreign_key: { to_table: :users }
      t.references :employer, type: :string, null: false, foreign_key: { to_table: :users }
      t.references :job, type: :string, foreign_key: true
      t.timestamps
    end
    add_index :conversations, %i[candidate_id employer_id job_id], unique: true

    create_table :messages, id: :string do |t|
      t.references :conversation, type: :string, null: false, foreign_key: true
      t.references :sender, type: :string, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :read_at
      t.timestamps
    end

    create_table :application_events, id: :string do |t|
      t.references :application, type: :string, null: false, foreign_key: true
      t.references :actor, type: :string, foreign_key: { to_table: :users }
      t.string :event_type, :from_status, :to_status
      t.text :note
      t.timestamps
    end

    create_table :acts, id: :string do |t|
      t.references :owner, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :name, :act_type, :currency, :fee_basis, :status, null: false
      t.string :tagline, :city, :tech_rider_url, :hospitality_rider_url, :promo_url
      t.text :bio
      t.jsonb :genres, :languages, :event_types, default: [], null: false
      t.integer :lineup_size, default: 1, null: false
      t.integer :min_fee, :max_fee, :travel_radius_km
      t.boolean :travels_nationally, :travels_internationally, :verified, default: false, null: false
      t.timestamps
    end

    create_table :act_members, id: :string do |t|
      t.references :act, type: :string, null: false, foreign_key: true
      t.references :user, type: :string, foreign_key: true
      t.string :display_name, :role_name, :instrument, :member_status, null: false
      t.boolean :is_leader, default: false, null: false
      t.timestamps
    end

    create_table :booking_requests, id: :string do |t|
      t.references :act, type: :string, null: false, foreign_key: true
      t.references :requester, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :event_type, :city, :currency, :status, null: false
      t.string :event_name, :start_time, :venue_name, :venue_address, :indoor_outdoor
      t.datetime :event_date
      t.integer :duration_minutes, :audience_size, :budget_min, :budget_max
      t.text :requirements
      t.jsonb :production_provided, default: [], null: false
      t.boolean :travel_provided, :accommodation_provided, default: false, null: false
      t.timestamps
    end

    create_table :booking_quotes, id: :string do |t|
      t.references :booking_request, type: :string, null: false, foreign_key: true
      t.references :created_by, type: :string, null: false, foreign_key: { to_table: :users }
      t.integer :performance_fee, null: false
      t.integer :travel_fee, :production_fee, :other_fee, default: 0, null: false
      t.string :currency, :status, null: false
      t.integer :deposit_percent, default: 50, null: false
      t.datetime :valid_until
      t.text :inclusions, :exclusions, :cancellation_terms
      t.timestamps
    end

    create_table :booking_payments, id: :string do |t|
      t.references :booking_request, type: :string, null: false, foreign_key: true
      t.references :booking_quote, type: :string, foreign_key: true
      t.references :payer, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :kind, :currency, :provider, :provider_order_id, :provider_payment_id, :status, null: false
      t.integer :amount, null: false
      t.timestamps
    end

    create_table :organizations, id: :string do |t|
      t.references :owner, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :name, :status, null: false
      t.string :org_type, :website, :city, :tax_id, :billing_email
      t.timestamps
    end

    create_table :organization_members, id: false do |t|
      t.references :organization, type: :string, null: false, foreign_key: true
      t.references :user, type: :string, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.datetime :created_at, null: false
    end
    add_index :organization_members, %i[organization_id user_id], unique: true

    create_table :urgent_requests, id: :string do |t|
      t.references :requester, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :title, :role_name, :city, :currency, :status, null: false
      t.string :instrument, :genre
      t.datetime :start_at, :end_at
      t.integer :budget_min, :budget_max
      t.text :requirements
      t.boolean :travel_covered, default: false, null: false
      t.timestamps
    end

    create_table :urgent_request_responses, id: false do |t|
      t.references :urgent_request, type: :string, null: false, foreign_key: true
      t.references :user, type: :string, null: false, foreign_key: true
      t.text :message
      t.integer :rate
      t.string :status, null: false, default: "available"
      t.timestamps
    end
    add_index :urgent_request_responses, %i[urgent_request_id user_id], unique: true, name: :idx_urgent_response_unique

    create_table :talent_folders, id: :string do |t|
      t.references :owner, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    create_table :talent_folder_members, id: false do |t|
      t.references :talent_folder, type: :string, null: false, foreign_key: true
      t.references :candidate, type: :string, null: false, foreign_key: { to_table: :users }
      t.text :note
      t.datetime :created_at, null: false
    end
    add_index :talent_folder_members, %i[talent_folder_id candidate_id], unique: true, name: :idx_talent_folder_member_unique

    create_table :band_projects, id: :string do |t|
      t.references :owner, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :name, :status, null: false
      t.string :city, :commitment_type, :rehearsal_schedule, :compensation_model
      t.text :concept
      t.jsonb :genres, default: [], null: false
      t.timestamps
    end

    create_table :band_project_roles, id: :string do |t|
      t.references :band_project, type: :string, null: false, foreign_key: true
      t.references :opportunity, type: :string, foreign_key: { to_table: :jobs }
      t.string :role_name, :status, null: false
      t.string :instrument, :skill_level, :compensation
      t.integer :count_needed, default: 1, null: false
      t.text :requirements
      t.timestamps
    end

    create_table :crew_plans, id: :string do |t|
      t.references :owner, type: :string, null: false, foreign_key: { to_table: :users }
      t.string :title, :event_type, :city, :currency, null: false
      t.datetime :event_date
      t.integer :audience_size, :budget
      t.jsonb :genres, :needs, default: [], null: false
      t.text :notes
      t.timestamps
    end

    create_table :crew_plan_roles, id: :string do |t|
      t.references :crew_plan, type: :string, null: false, foreign_key: true
      t.string :category, :role_name, :instrument, :priority, null: false
      t.integer :count_needed, default: 1, null: false
      t.text :rationale
      t.timestamps
    end

    create_table :billing_events, id: :string do |t|
      t.string :provider, :provider_event_id, :event_type, null: false
      t.references :user, type: :string, foreign_key: true
      t.jsonb :payload, default: {}, null: false
      t.datetime :processed_at, null: false
      t.timestamps
    end
    add_index :billing_events, %i[provider provider_event_id], unique: true

    create_table :active_storage_blobs, id: :bigserial do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
      t.index :key, unique: true
    end
    create_table :active_storage_attachments, id: :bigserial do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.datetime :created_at, null: false
      t.index %i[record_type record_id name blob_id], unique: true, name: :index_active_storage_attachments_uniqueness
    end
  end
end
