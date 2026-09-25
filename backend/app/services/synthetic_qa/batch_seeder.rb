module SyntheticQa
  class BatchSeeder
    Result = Data.define(:batch, :jobseekers, :employers, :jobs, :applications, :conversations, :bookings)
    CITIES = %w[Mumbai Delhi Bengaluru Kolkata Chennai Hyderabad Pune Jaipur].freeze
    ROLES = ["Vocalist", "Guitarist", "Music Producer", "FOH Engineer", "Composer", "Tour Manager", "Drummer", "Keyboardist"].freeze
    GENRES = ["Bollywood", "Indie Pop", "Rock", "Jazz", "Hip-Hop", "Classical", "EDM", "Folk"].freeze

    def self.call(...) = new(...).call

    def initialize(batch:, jobseekers: 225, employers: 75, password: nil)
      @batch = batch.to_s
      @jobseeker_count = Integer(jobseekers)
      @employer_count = Integer(employers)
      @password = password.presence || ENV["SYNTHETIC_QA_PASSWORD"].presence || "SyntheticPass123!"
    end

    def call
      guard!
      existing = User.synthetic(batch).count
      raise ArgumentError, "Synthetic batch #{batch.inspect} already contains #{existing} users; purge it before reseeding." if existing.positive?

      result = nil
      ApplicationRecord.transaction do
        digest = BCrypt::Password.create(password)
        jobseekers = Array.new(jobseeker_count) { |index| create_jobseeker(index, digest) }
        employers = Array.new(employer_count) { |index| create_employer(index, digest) }
        jobs = employers.map.with_index { |employer, index| create_job(employer, index) }

        applications = jobseekers.map.with_index do |candidate, index|
          job = jobs.fetch(index % jobs.length)
          create_candidate_graph(candidate, job, index)
        end
        create_employer_graph(employers, jobseekers, jobs)
        conversations = create_conversations(applications)
        bookings = create_booking_graph(employers, jobseekers)

        result = Result.new(batch:, jobseekers: jobseekers.size, employers: employers.size, jobs: jobs.size,
          applications: applications.size, conversations: conversations.size, bookings: bookings.size)
      end
      result
    end

    private

    attr_reader :batch, :jobseeker_count, :employer_count, :password

    def guard!
      unless Rails.env.test? || Rails.env.development? || ENV["ALLOW_SYNTHETIC_QA"] == "true"
        raise SecurityError, "Synthetic QA data is disabled. Set ALLOW_SYNTHETIC_QA=true for an explicitly approved environment."
      end
      raise ArgumentError, "Batch must use 3-64 lowercase letters, numbers or hyphens." unless batch.match?(/\A[a-z0-9][a-z0-9-]{2,63}\z/)
      raise ArgumentError, "Create between 1 and 1,000 accounts per role." unless jobseeker_count.between?(1, 1_000) && employer_count.between?(1, 1_000)
      raise ArgumentError, "Synthetic password must be at least 10 characters." if password.length < 10
      raise ArgumentError, "At least one synthetic employer is required." if employer_count.zero?
    end

    def create_jobseeker(index, digest)
      role_name = ROLES[index % ROLES.length]
      city = CITIES[index % CITIES.length]
      genre = GENRES[index % GENRES.length]
      user = User.create!(name: "QA #{role_name} #{index + 1}", email: email_for("professional", index),
        password_digest: digest, role: "jobseeker", status: "active", email_verified: true,
        profile_complete: true, synthetic_batch: batch)
      user.create_profile!(headline: "#{role_name} · #{genre}", location: city, bio: "Synthetic QA profile for reversible end-to-end testing.",
        skills: [role_name, "Collaboration"], genres: [genre], instruments: [role_name], languages: %w[Hindi English],
        roles: [role_name], open_to: %w[sessions touring freelance], years_experience: (index % 12) + 1,
        remote_recording: index.even?, travels_nationally: true, currency: "INR", day_rate: 5_000 + (index % 10) * 1_000)
      user.portfolio_items.create!(kind: "audio", title: "QA work sample #{index + 1}",
        url: "https://example.com/qa/#{batch}/portfolio/#{index + 1}", visibility: "public", tags: [role_name], genres: [genre], roles: [role_name])
      user.availability_windows.create!(start_at: 2.weeks.from_now + index.hours, end_at: 2.weeks.from_now + index.hours + 4.hours,
        status: index % 5 == 0 ? "tentative" : "available", city: city, note: "Synthetic QA window")
      user.job_alerts.create!(name: "QA #{role_name} alerts", query: role_name, location: city, frequency: "daily", active: true)
      user.notifications.create!(kind: "qa", title: "Synthetic account ready", body: "Batch #{batch}")
      user
    end

    def create_employer(index, digest)
      city = CITIES[index % CITIES.length]
      user = User.create!(name: "QA Employer #{index + 1}", email: email_for("employer", index),
        password_digest: digest, role: "employer", status: "active", email_verified: true,
        profile_complete: true, synthetic_batch: batch)
      user.create_profile!(company_name: "QA Music Company #{index + 1}", company_website: "https://example.com/qa/#{batch}/company/#{index + 1}",
        company_size: "11-50", company_description: "Synthetic employer for reversible end-to-end testing.", location: city)
      user.subscriptions.create!(plan_code: index % 4 == 0 ? "studio" : "pro", provider: "internal", status: "active",
        current_period_start: Time.current, current_period_end: 30.days.from_now)
      organization = user.organizations.create!(name: "QA Workspace #{index + 1}", status: "active", org_type: "studio", city: city,
        billing_email: user.email)
      organization.organization_members.create!(user:, role: "owner")
      user
    end

    def create_job(employer, index)
      role_name = ROLES[index % ROLES.length]
      Job.create!(employer:, title: "QA #{role_name} opportunity #{index + 1}", company: employer.profile.company_name,
        location: employer.profile.location, kind: "Contract", genre: GENRES[index % GENRES.length],
        description: "Synthetic published opportunity used to verify discovery, application, messaging and hiring workflows end to end.",
        requirements: "Demonstrable work samples and professional communication.", skills: [role_name], languages: %w[Hindi English],
        screening_questions: ["Share one relevant credit."], status: "published", opportunity_kind: index.even? ? "job" : "gig",
        function_area: "Performance", workplace: index % 3 == 0 ? "remote" : "onsite", currency: "INR",
        compensation_min: 15_000, compensation_max: 35_000, compensation_period: "project", slots: 1, paid: true,
        portfolio_required: true, published_at: Time.current)
    end

    def create_candidate_graph(candidate, job, index)
      application = job.applications.create!(candidate:, status: application_status(index),
        cover_letter: "Synthetic application for batch #{batch}.", screening_answers: ["QA credit #{index + 1}"])
      candidate.saved_jobs.create!(job:)
      application.application_events.create!(actor: candidate, event_type: "created", to_status: "Applied", note: "Synthetic QA event")
      application
    end

    def create_employer_graph(employers, jobseekers, jobs)
      employers.each_with_index do |employer, index|
        candidate = jobseekers[index % jobseekers.length]
        TalentShortlist.create!(employer:, candidate:, note: "Synthetic shortlist")
        folder = employer.talent_folders.create!(name: "QA Shortlist #{index + 1}", description: "Batch #{batch}")
        folder.talent_folder_members.create!(candidate:, note: "Synthetic folder member")
        candidate.reviews.create!(employer:, rating: (index % 5) + 1, title: "QA collaboration", body: "Synthetic review for cleanup and moderation testing.", status: "pending")
        employer.verification_requests.create!(kind: "organization", evidence_url: "https://example.com/qa/#{batch}/verification/#{index + 1}", note: "Synthetic verification")
        employer.reports.create!(entity_type: "Job", entity_id: jobs[index].id, reason: "qa-test", status: "open", details: "Synthetic report")

        project = employer.band_projects.create!(name: "QA Band Project #{index + 1}", status: "planning", city: employer.profile.location,
          concept: "Synthetic project", genres: [GENRES[index % GENRES.length]])
        project.band_project_roles.create!(role_name: ROLES[index % ROLES.length], status: "open", count_needed: 1,
          requirements: "Synthetic role", opportunity: jobs[index])
        plan = employer.crew_plans.create!(title: "QA Crew Plan #{index + 1}", event_type: "Concert", city: employer.profile.location,
          currency: "INR", event_date: 2.months.from_now, audience_size: 500, budget: 250_000, genres: [GENRES[index % GENRES.length]], needs: %w[music sound])
        plan.crew_plan_roles.create!(category: "music", role_name: ROLES[index % ROLES.length], priority: "required", count_needed: 1,
          rationale: "Synthetic recommendation")
        urgent = employer.urgent_requests.create!(title: "QA urgent #{ROLES[index % ROLES.length]}", role_name: ROLES[index % ROLES.length],
          city: employer.profile.location, currency: "INR", status: "open", start_at: 10.days.from_now, end_at: 11.days.from_now,
          budget_min: 8_000, budget_max: 15_000, requirements: "Synthetic urgent request")
        urgent.urgent_request_responses.create!(user: candidate, message: "Synthetic availability response", rate: 10_000, status: "available")
      end
    end

    def create_conversations(applications)
      applications.map do |application|
        conversation = Conversation.create!(candidate: application.candidate, employer: application.job.employer, job: application.job)
        conversation.messages.create!(sender: application.candidate, body: "Synthetic candidate message for #{batch}.")
        conversation.messages.create!(sender: application.job.employer, body: "Synthetic employer reply for #{batch}.")
        conversation
      end
    end

    def create_booking_graph(employers, jobseekers)
      acts = jobseekers.first([jobseekers.length, employers.length].min).map.with_index do |owner, index|
        act = owner.owned_acts.create!(name: "QA Act #{index + 1}", act_type: index.even? ? "band" : "solo", currency: "INR",
          fee_basis: "event", status: "active", city: owner.profile.location, bio: "Synthetic bookable act.",
          genres: owner.profile.genres, languages: %w[Hindi English], event_types: %w[wedding corporate], lineup_size: 1,
          min_fee: 25_000, max_fee: 50_000, travels_nationally: true)
        act.act_members.create!(user: owner, display_name: owner.name, role_name: owner.profile.roles.first,
          member_status: "confirmed", is_leader: true)
        act
      end

      employers.map.with_index do |requester, index|
        act = acts[index % acts.length]
        booking = act.booking_requests.create!(requester:, event_type: "corporate", city: requester.profile.location, currency: "INR",
          status: "quoted", event_name: "QA Event #{index + 1}", event_date: 45.days.from_now + index.hours, duration_minutes: 120,
          audience_size: 300, budget_min: 40_000, budget_max: 80_000, requirements: "Synthetic booking request")
        quote = booking.booking_quotes.create!(created_by: act.owner, performance_fee: 45_000, travel_fee: 5_000,
          production_fee: 0, other_fee: 0, currency: "INR", status: "sent", deposit_percent: 50,
          valid_until: 10.days.from_now, inclusions: "Performance", exclusions: "Production", cancellation_terms: "Synthetic terms")
        booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "deposit", currency: "INR",
          provider: "internal", status: "created", amount: 25_000)
        booking
      end
    end

    def application_status(index)
      ["Applied", "Under Review", "Shortlisted", "Interview Scheduled", "Offer", "Hired", "Rejected"][index % 7]
    end

    def email_for(kind, index) = "qa+#{batch}-#{kind}-#{format('%04d', index + 1)}@example.invalid"
  end
end
