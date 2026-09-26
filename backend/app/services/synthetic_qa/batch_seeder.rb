module SyntheticQa
  # Creates a tagged, reversible batch of synthetic users and a representative graph that
  # exercises every marketplace screen. Remove it with SyntheticQa::BatchCleanup.
  #
  # Two entry points:
  # * rake synthetic_qa:seed (local QA / explicitly approved environments via ALLOW_SYNTHETIC_QA);
  #   an explicit password keeps QA logins possible.
  # * the admin demo-data job (authorized_by: an active admin, batch "demo-*"): allowed in
  #   production without an env flag, capped at Demo::MAX_USERS demo users in total, and
  #   seeded with a random per-batch password that is never returned or logged.
  class BatchSeeder
    Result = Data.define(:batch, :jobseekers, :employers, :jobs, :applications, :conversations, :bookings)
    CITIES = %w[Mumbai Delhi Bengaluru Kolkata Chennai Hyderabad Pune Jaipur Goa Kochi].freeze
    ROLES = ["Vocalist", "Guitarist", "Music Producer", "FOH Engineer", "Composer", "Tour Manager", "Drummer", "Keyboardist",
      "Bassist", "Violinist", "Tabla Player", "Mixing Engineer"].freeze
    INSTRUMENTS = { "Vocalist" => "Vocals", "Guitarist" => "Guitar", "Drummer" => "Drums", "Keyboardist" => "Keys", "Bassist" => "Bass",
      "Violinist" => "Violin", "Tabla Player" => "Tabla" }.freeze
    GENRES = ["Bollywood", "Indie Pop", "Rock", "Jazz", "Hip-Hop", "Classical", "EDM", "Folk", "Sufi", "Fusion"].freeze
    OPPORTUNITY_KINDS = %w[job gig audition session tour internship collaboration].freeze
    FUNCTION_AREAS = ["Performance", "Production", "Live Sound", "Composition", "Touring", "Management"].freeze
    WORKPLACES = %w[onsite hybrid remote travel].freeze
    APPLICATION_STATUSES = ["Applied", "Under Review", "Shortlisted", "Interview Scheduled", "Offer", "Hired", "Rejected"].freeze
    # Every employer gets one "quoted" booking (QA journeys rely on it) plus one in each other state in rotation.
    EXTRA_BOOKING_STATUSES = %w[requested viewed negotiating accepted completed disputed declined cancelled].freeze
    FIRST_NAMES = %w[Aarav Ananya Kabir Meera Rohan Ishita Vikram Priya Arjun Nandini Siddharth Tara Dev Kavya Aditya Zoya
      Neel Riya Farhan Sana Karan Aditi Rahul Leela Omar Pooja Varun Shreya Imran Diya].freeze
    LAST_NAMES = %w[Sharma Iyer Menon Kapoor Das Banerjee Reddy Nair Mehta Singh Rao Khan Fernandes Chatterjee Joshi Pillai Bose Gill].freeze
    COMPANY_PREFIXES = %w[Saffron Monsoon Indigo Banyan Copper Lotus Riverbend Kestrel Marigold Northstar Tamarind Velvet].freeze
    COMPANY_SUFFIXES = ["Sound Studios", "Live Events", "Records", "Stage Productions", "Wedding Co.", "Music Collective", "Touring"].freeze
    EVENTS = ["a 12-city indie tour", "a destination wedding", "a corporate gala", "an album session", "a festival headline set",
      "a web-series soundtrack", "a jazz club residency", "a brand launch"].freeze

    def self.call(...) = new(...).call

    def initialize(batch:, jobseekers: 225, employers: 75, password: nil, authorized_by: nil)
      @batch = batch.to_s
      @jobseeker_count = Integer(jobseekers)
      @employer_count = Integer(employers)
      @authorized_by = authorized_by
      @demo = Demo.batch?(@batch)
      # Demo batches are public, so they never get a known password unless one is passed explicitly (local QA).
      @password = password.presence || (@demo ? SecureRandom.base58(40) : ENV["SYNTHETIC_QA_PASSWORD"].presence || "SyntheticPass123!")
    end

    def call
      guard!
      existing = User.synthetic(batch).count
      raise ArgumentError, "Synthetic batch #{batch.inspect} already contains #{existing} users; purge it before reseeding." if existing.positive?

      result = nil
      ApplicationRecord.transaction do
        digest = BCrypt::Password.create(password)
        @password = nil
        jobseekers = Array.new(jobseeker_count) { |index| create_jobseeker(index, digest) }
        employers = Array.new(employer_count) { |index| create_employer(index, digest) }
        primary_jobs = employers.map.with_index { |employer, index| create_job(employer, index, index) }
        extra_jobs = employers.map.with_index { |employer, index| create_job(employer, employer_count + index, index, secondary: true) }

        applications = jobseekers.map.with_index do |candidate, index|
          create_candidate_graph(candidate, primary_jobs.fetch(index % primary_jobs.length), index)
        end
        create_employer_graph(employers, jobseekers, primary_jobs)
        conversations = create_conversations(applications)
        bookings = create_booking_graph(employers, jobseekers)

        result = Result.new(batch:, jobseekers: jobseekers.size, employers: employers.size, jobs: primary_jobs.size + extra_jobs.size,
          applications: applications.size, conversations: conversations.size, bookings: bookings.size)
      end
      result
    end

    private

    attr_reader :batch, :jobseeker_count, :employer_count, :password, :authorized_by

    def demo? = @demo

    def guard!
      raise ArgumentError, "Batch must use 3-64 lowercase letters, numbers or hyphens." unless batch.match?(/\A[a-z0-9][a-z0-9-]{2,63}\z/)
      if authorized_by
        raise SecurityError, "Only an active admin can create demo data." unless authorized_by.admin? && authorized_by.active?
        raise ArgumentError, "Admin-created batches must be named demo-*." unless demo?
        total = Demo.users.count + jobseeker_count + employer_count
        raise ArgumentError, "Demo data is capped at #{Demo::MAX_USERS} users (this would make #{total}). Delete existing demo data first." if total > Demo::MAX_USERS
      elsif !(Rails.env.test? || Rails.env.development? || ENV["ALLOW_SYNTHETIC_QA"] == "true")
        raise SecurityError, "Synthetic QA data is disabled. Set ALLOW_SYNTHETIC_QA=true for an explicitly approved environment."
      end
      raise ArgumentError, "Create between 1 and 1,000 accounts per role." unless jobseeker_count.between?(1, 1_000) && employer_count.between?(1, 1_000)
      raise ArgumentError, "Synthetic password must be at least 10 characters." if password.length < 10
    end

    def create_jobseeker(index, digest)
      role_name = ROLES[index % ROLES.length]
      second_role = ROLES[(index + 5) % ROLES.length]
      city = CITIES[index % CITIES.length]
      genre = GENRES[index % GENRES.length]
      second_genre = GENRES[(index + 3) % GENRES.length]
      name = demo? ? person_name(index) : "QA #{role_name} #{index + 1}"
      user = User.create!(name:, email: email_for("professional", index),
        password_digest: digest, role: "jobseeker", status: "active", email_verified: true,
        profile_complete: true, synthetic_batch: batch)
      user.create_profile!(headline: "#{role_name} · #{genre} & #{second_genre}", location: city,
        bio: demo? ? "#{role_name} based in #{city} with #{(index % 12) + 2} years across #{genre.downcase} and #{second_genre.downcase} projects. Comfortable in the studio and on stage; reads charts and works fast with producers." : "Synthetic QA profile for reversible end-to-end testing.",
        skills: [role_name, second_role, "Collaboration", "Session work"], genres: [genre, second_genre], instruments: [INSTRUMENTS.fetch(role_name, "Laptop")],
        languages: %w[Hindi English], roles: [role_name, second_role], open_to: %w[sessions touring freelance],
        credits: ["#{EVENTS[index % EVENTS.length].sub(/\Aan? /, '').capitalize} (#{2020 + (index % 6)})", "Live set at #{CITIES[(index + 2) % CITIES.length]} music week"],
        gear: ["In-ear monitors", "Personal mic kit"], software: ["Logic Pro", "Ableton Live"].rotate(index % 2),
        years_experience: (index % 12) + 2, experience: "#{(index % 12) + 2} years", availability: index.even? ? "Available this month" : "Booking from next month",
        remote_recording: index.even?, sight_reading: index % 3 == 0, travels_nationally: true, passport_ready: index % 4 == 0,
        currency: "INR", day_rate: 5_000 + (index % 10) * 1_000, session_rate: 3_000 + (index % 6) * 500, show_rate: 12_000 + (index % 8) * 2_000,
        website: "https://example.com/#{batch}/artist/#{index + 1}")
      user.portfolio_items.create!(kind: "video", title: demo? ? "#{genre} live session" : "QA work sample #{index + 1}",
        url: "https://www.youtube.com/watch?v=verseDemo#{format('%03d', index % 1000)}", visibility: "public", featured: true,
        description: "Placeholder video link for demo data.", credited_as: role_name, year: 2020 + (index % 6),
        tags: [role_name, "Live"], genres: [genre], roles: [role_name])
      user.portfolio_items.create!(kind: "audio", title: demo? ? "#{second_genre} studio demo" : "QA audio sample #{index + 1}",
        url: "https://example.com/#{batch}/portfolio/#{index + 1}.mp3", visibility: "public", sort_order: 1,
        description: "Placeholder audio link for demo data.", credited_as: second_role, year: 2021 + (index % 5),
        tags: [second_role], genres: [second_genre], roles: [second_role])
      user.availability_windows.create!(start_at: 2.weeks.from_now + index.hours, end_at: 2.weeks.from_now + index.hours + 4.hours,
        status: index % 5 == 0 ? "tentative" : "available", city:, note: "Open for sessions")
      user.availability_windows.create!(start_at: 5.weeks.from_now + index.hours, end_at: 5.weeks.from_now + index.hours + 1.day,
        status: %w[booked hold unavailable][index % 3], city: CITIES[(index + 1) % CITIES.length], note: "Tour date")
      user.job_alerts.create!(name: "#{role_name} alerts", query: role_name, location: city, frequency: index.even? ? "daily" : "weekly", active: true)
      user.notifications.create!(kind: "welcome", title: "Profile ready", body: "Your profile is live on Verse.", link: "/jobseeker/profile")
      user.notifications.create!(kind: "job_alert", title: "New #{role_name} opportunities", body: "3 new matches in #{city}.", link: "/jobseeker/jobs",
        read_at: index.even? ? 1.day.ago : nil)
      user
    end

    def create_employer(index, digest)
      city = CITIES[index % CITIES.length]
      company = demo? ? company_name(index) : "QA Music Company #{index + 1}"
      user = User.create!(name: demo? ? person_name(index + 11) : "QA Employer #{index + 1}", email: email_for("employer", index),
        password_digest: digest, role: "employer", status: "active", email_verified: true,
        profile_complete: true, synthetic_batch: batch)
      user.create_profile!(company_name: company, company_website: "https://example.com/#{batch}/company/#{index + 1}",
        company_size: ["1-10", "11-50", "51-200"][index % 3], location: city, headline: "Hiring musicians and crew in #{city}",
        company_description: demo? ? "#{company} produces live shows, sessions and events across #{city} and beyond." : "Synthetic employer for reversible end-to-end testing.")
      user.subscriptions.create!(plan_code: index % 4 == 0 ? "studio" : "pro", provider: "internal", status: "active",
        current_period_start: Time.current, current_period_end: 30.days.from_now)
      organization = user.organizations.create!(name: demo? ? "#{company} team" : "QA Workspace #{index + 1}", status: "active",
        org_type: "studio", city:, billing_email: user.email)
      organization.organization_members.create!(user:, role: "owner")
      user.notifications.create!(kind: "billing", title: "Plan active", body: "Your #{index % 4 == 0 ? 'Studio' : 'Pro'} plan is active.", link: "/employer/billing")
      user
    end

    def create_job(employer, index, employer_index, secondary: false)
      role_name = ROLES[index % ROLES.length]
      kind = OPPORTUNITY_KINDS[index % OPPORTUNITY_KINDS.length]
      status = secondary ? %w[published published closed draft][employer_index % 4] : "published"
      city = secondary ? CITIES[(employer_index + 3) % CITIES.length] : employer.profile.location
      title = demo? ? "#{role_name} for #{EVENTS[index % EVENTS.length]}" : "QA #{role_name} opportunity #{index + 1}"
      Job.create!(employer:, title:, company: employer.profile.company_name,
        location: city, kind: %w[Contract Freelance Full-time Part-time][index % 4], genre: GENRES[index % GENRES.length],
        description: demo? ? "#{employer.profile.company_name} is looking for a #{role_name.downcase} for #{EVENTS[index % EVENTS.length]} in #{city}. Rehearsals, travel and schedule are shared after shortlisting." : "Synthetic published opportunity used to verify discovery, application, messaging and hiring workflows end to end.",
        requirements: "Demonstrable work samples and professional communication.", skills: [role_name, GENRES[index % GENRES.length]], languages: %w[Hindi English],
        screening_questions: ["Share one relevant credit."], status:, opportunity_kind: kind,
        function_area: FUNCTION_AREAS[index % FUNCTION_AREAS.length], workplace: WORKPLACES[index % WORKPLACES.length], currency: "INR",
        compensation_min: 15_000 + (index % 5) * 5_000, compensation_max: 35_000 + (index % 5) * 10_000, compensation_period: "project",
        slots: (index % 3) + 1, paid: true, featured: index % 9 == 0, portfolio_required: true,
        experience_level: %w[entry mid senior][index % 3], application_deadline: 3.weeks.from_now + index.hours,
        start_date: 5.weeks.from_now, published_at: status == "draft" ? nil : Time.current)
    end

    def create_candidate_graph(candidate, job, index)
      status = APPLICATION_STATUSES[index % APPLICATION_STATUSES.length]
      application = job.applications.create!(candidate:, status:, cover_letter: demo? ? "I'd love to be part of this — my recent work is on my profile." : "Synthetic application for batch #{batch}.",
        screening_answers: ["Credit #{index + 1}"])
      candidate.saved_jobs.create!(job:)
      application.application_events.create!(actor: candidate, event_type: "created", to_status: "Applied", note: "Application submitted")
      application.application_events.create!(actor: job.employer, event_type: "status_changed", from_status: "Applied", to_status: status, note: "Status updated") unless status == "Applied"
      candidate.notifications.create!(kind: "application_status", title: "Application #{status.downcase}", body: "#{job.title}: #{status}.", link: "/jobseeker/applications")
      job.employer.notifications.create!(kind: "application", title: "New application", body: "#{candidate.name} applied to #{job.title}.", link: "/hiring/applicants")
      application
    end

    def create_employer_graph(employers, jobseekers, jobs)
      employers.each_with_index do |employer, index|
        candidate = jobseekers[index % jobseekers.length]
        genre = GENRES[index % GENRES.length]
        role_name = ROLES[index % ROLES.length]
        city = employer.profile.location
        TalentShortlist.create!(employer:, candidate:, note: "Strong fit for upcoming shows")
        folder = employer.talent_folders.create!(name: "#{genre} shortlist", description: "Batch #{batch}")
        folder.talent_folder_members.create!(candidate:, note: "Available next month")
        candidate.reviews.create!(employer:, rating: [5, 4, 5, 3, 4][index % 5], title: "Great collaboration", status: %w[published published pending rejected][index % 4],
          body: demo? ? "Clear brief, paid on time and a well-run production." : "Synthetic review for cleanup and moderation testing.")
        second = jobseekers[(index + 1) % jobseekers.length]
        second.reviews.create!(employer:, rating: 4, title: "Professional team", body: "Organised rehearsals and fair terms.", status: "published") if second != candidate
        employer.verification_requests.create!(kind: "organization", evidence_url: "https://example.com/#{batch}/verification/#{index + 1}", note: "Company registration")
        employer.reports.create!(entity_type: "Job", entity_id: jobs[index].id, reason: "qa-test", status: "open", details: demo? ? "Demo report (safe to dismiss)." : "Synthetic report")

        project = employer.band_projects.create!(name: "#{genre} ensemble #{index + 1}", status: %w[planning recruiting active][index % 3], city:,
          concept: "Building a #{genre.downcase} ensemble for #{EVENTS[index % EVENTS.length]}.", genres: [genre])
        project.band_project_roles.create!(role_name:, status: "open", count_needed: 1, requirements: "Strong live experience", opportunity: jobs[index])
        project.band_project_roles.create!(role_name: ROLES[(index + 4) % ROLES.length], status: "filled", count_needed: 1, requirements: "Confirmed")
        plan = employer.crew_plans.create!(title: "#{genre} night crew", event_type: "Concert", city:,
          currency: "INR", event_date: 2.months.from_now, audience_size: 500, budget: 250_000, genres: [genre], needs: %w[music sound])
        plan.crew_plan_roles.create!(category: "music", role_name:, priority: "required", count_needed: 1, rationale: "Core lineup")
        urgent = employer.urgent_requests.create!(title: "Urgent: #{role_name} needed in #{city}", role_name:,
          city:, currency: "INR", status: %w[open open filled cancelled][index % 4], start_at: 10.days.from_now, end_at: 11.days.from_now,
          budget_min: 8_000, budget_max: 15_000, requirements: "Short-notice replacement for a confirmed show.")
        urgent.urgent_request_responses.create!(user: candidate, message: "Available and can travel.", rate: 10_000, status: "available")
      end
    end

    def create_conversations(applications)
      applications.map.with_index do |application, index|
        candidate = application.candidate
        employer = application.job.employer
        conversation = Conversation.create!(candidate:, employer:, job: application.job)
        if demo?
          conversation.messages.create!(sender: candidate, body: "Hi! I applied for #{application.job.title}. Happy to share more samples.")
          conversation.messages.create!(sender: employer, body: "Thanks — loved your live session. Are you free for a call this week?")
          conversation.messages.create!(sender: candidate, body: "Yes, Thursday afternoon works for me.") if index.even?
        else
          conversation.messages.create!(sender: candidate, body: "Synthetic candidate message for #{batch}.")
          conversation.messages.create!(sender: employer, body: "Synthetic employer reply for #{batch}.")
        end
        candidate.notifications.create!(kind: "message", title: "New message", body: "#{employer.name} replied.", link: "/messages")
        conversation
      end
    end

    def create_booking_graph(employers, jobseekers)
      act_count = [jobseekers.length, employers.length].min
      acts = jobseekers.first(act_count).map.with_index do |owner, index|
        band = index.even?
        genre = owner.profile.genres.first
        act = owner.owned_acts.create!(name: demo? ? "#{owner.name.split.last} #{band ? "#{genre} Collective" : 'Live'}" : "QA Act #{index + 1}",
          act_type: band ? "band" : "solo", currency: "INR", fee_basis: "event", status: "active", city: owner.profile.location,
          tagline: "#{genre} for weddings, clubs and corporate stages", bio: demo? ? "A #{band ? 'band' : 'solo act'} from #{owner.profile.location} playing #{genre.downcase} sets." : "Synthetic bookable act.",
          genres: owner.profile.genres, languages: %w[Hindi English], event_types: %w[wedding corporate club festival].first(2 + (index % 3)),
          lineup_size: band ? 3 : 1, min_fee: 25_000, max_fee: 50_000 + (index % 5) * 10_000, travels_nationally: true,
          promo_url: "https://example.com/#{batch}/act/#{index + 1}")
        act.act_members.create!(user: owner, display_name: owner.name, role_name: owner.profile.roles.first,
          member_status: "confirmed", is_leader: true)
        if band && jobseekers.length > act_count + 1
          [act_count + index, act_count + index + 1].map { jobseekers[_1 % jobseekers.length] }.uniq.reject { _1 == owner }.each do |member|
            act.act_members.create!(user: member, display_name: member.name, role_name: member.profile.roles.first, instrument: member.profile.instruments.first, member_status: "confirmed")
          end
        end
        act
      end

      employers.each_with_index.flat_map do |requester, index|
        quoted = create_booking(acts[index % acts.length], requester, "quoted", index)
        extra_status = EXTRA_BOOKING_STATUSES[index % EXTRA_BOOKING_STATUSES.length]
        extra = create_booking(acts[(index + 1) % acts.length], requester, extra_status, index + employers.length)
        [quoted, extra]
      end
    end

    def create_booking(act, requester, status, index)
      booking = act.booking_requests.create!(requester:, event_type: %w[corporate wedding club festival][index % 4], city: requester.profile.location, currency: "INR",
        status:, event_name: demo? ? "#{requester.profile.company_name} #{%w[gala wedding showcase festival][index % 4]}" : "QA Event #{index + 1}",
        event_date: (status == "completed" ? 20.days.ago : 45.days.from_now) + index.hours, duration_minutes: 120,
        audience_size: 300, budget_min: 40_000, budget_max: 80_000, requirements: demo? ? "Two 45-minute sets, sound provided." : "Synthetic booking request")
      return booking if %w[requested viewed].include?(status)

      quote_status = %w[accepted completed disputed].include?(status) ? "accepted" : "sent"
      quote = booking.booking_quotes.create!(created_by: act.owner, performance_fee: 45_000, travel_fee: 5_000,
        production_fee: 0, other_fee: 0, currency: "INR", status: quote_status, deposit_percent: 50,
        valid_until: 10.days.from_now, inclusions: "Performance", exclusions: "Production", cancellation_terms: "50% deposit is non-refundable within 7 days.")
      case status
      when "quoted"
        booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "deposit", currency: "INR", provider: "internal", status: "created", amount: 25_000)
      when "accepted", "disputed"
        booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "deposit", currency: "INR", provider: "internal", status: "paid", amount: 25_000)
      when "completed"
        booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "deposit", currency: "INR", provider: "internal", status: "paid", amount: 25_000)
        booking.booking_payments.create!(booking_quote: quote, payer: requester, kind: "balance", currency: "INR", provider: "internal", status: "paid", amount: 25_000)
      end
      act.owner.notifications.create!(kind: "booking", title: "Booking #{status}", body: "#{booking.event_name} is #{status}.", link: "/bookings")
      booking
    end

    def person_name(index) = "#{FIRST_NAMES[index % FIRST_NAMES.length]} #{LAST_NAMES[(index * 7 + index / FIRST_NAMES.length) % LAST_NAMES.length]}"

    def company_name(index) = "#{COMPANY_PREFIXES[index % COMPANY_PREFIXES.length]} #{COMPANY_SUFFIXES[(index + index / COMPANY_PREFIXES.length) % COMPANY_SUFFIXES.length]}"

    def email_for(kind, index) = "qa+#{batch}-#{kind}-#{format('%04d', index + 1)}@example.invalid"
  end
end
