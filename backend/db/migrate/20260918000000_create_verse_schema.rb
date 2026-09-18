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
      t.string :availability, :currency, default: "INR"
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
      t.string :title, :company, :location, :kind, :genre, :salary, null: false
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
      t.string :title, :status, default: "pending", null: false
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
      t.string :action, :entity_type, :entity_id, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    create_table :career_resources, id: :string do |t|
      t.string :title, :category, :url, :status, null: false
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
      t.string :kind, :query, :entity_id, :label, null: false
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

    create_table :active_storage_blobs, id: :bigserial do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type, :metadata, :service_name, null: false
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
