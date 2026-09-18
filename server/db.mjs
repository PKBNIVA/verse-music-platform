import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import crypto from 'node:crypto';

export const now = () => new Date().toISOString();
export const uid = (prefix='id') => `${prefix}_${crypto.randomUUID()}`;

export function openDatabase(root) {
  const databasePath = process.env.DATABASE_PATH || join(root, 'data', 'verse.db');
  const dataDir = dirname(databasePath);
  mkdirSync(dataDir, { recursive: true });
  const db = new DatabaseSync(databasePath);
  db.exec('PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;');
  migrate(db);
  seed(db);
  return db;
}

function hasColumn(db, table, column) {
  return db.prepare(`PRAGMA table_info(${table})`).all().some((r) => r.name === column);
}
function addColumn(db, table, definition) {
  const column = definition.trim().split(/\s+/)[0];
  if (!hasColumn(db, table, column)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${definition}`);
}

function migrate(db) {
  db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE COLLATE NOCASE,
    role TEXT NOT NULL CHECK(role IN ('jobseeker','employer','admin')),
    password_hash TEXT NOT NULL, password_salt TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','pending')),
    profile_complete INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS profiles (
    user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    headline TEXT, bio TEXT, phone TEXT, location TEXT, experience TEXT,
    skills_json TEXT NOT NULL DEFAULT '[]', genres_json TEXT NOT NULL DEFAULT '[]',
    instruments_json TEXT NOT NULL DEFAULT '[]', website TEXT, portfolio_url TEXT,
    company_name TEXT, company_website TEXT, company_size TEXT, company_description TEXT,
    verified INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY, employer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL, company TEXT NOT NULL, location TEXT NOT NULL, type TEXT NOT NULL,
    genre TEXT NOT NULL, salary TEXT, description TEXT NOT NULL, requirements TEXT,
    skills_json TEXT NOT NULL DEFAULT '[]', experience_level TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('draft','pending','published','rejected','closed')),
    featured INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS applications (
    id TEXT PRIMARY KEY, job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    candidate_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    cover_letter TEXT, status TEXT NOT NULL DEFAULT 'Applied', interview_date TEXT,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, UNIQUE(job_id, candidate_id)
  );
  CREATE TABLE IF NOT EXISTS portfolio_items (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, title TEXT NOT NULL, url TEXT NOT NULL, description TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS conversations (
    id TEXT PRIMARY KEY, candidate_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id TEXT REFERENCES jobs(id) ON DELETE SET NULL, created_at TEXT NOT NULL,
    UNIQUE(candidate_id, employer_id, job_id)
  );
  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL, created_at TEXT NOT NULL, read_at TEXT
  );
  CREATE TABLE IF NOT EXISTS reviews (
    id TEXT PRIMARY KEY, author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    employer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5), title TEXT, body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','published','rejected')),
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS sessions (
    token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TEXT NOT NULL, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS audit_logs (
    id TEXT PRIMARY KEY, actor_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL, entity_type TEXT, entity_id TEXT, metadata_json TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS saved_jobs (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_id TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL, PRIMARY KEY(user_id, job_id)
  );
  CREATE TABLE IF NOT EXISTS job_alerts (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, query TEXT, location TEXT, opportunity_kind TEXT, function_area TEXT,
    remote_only INTEGER NOT NULL DEFAULT 0, frequency TEXT NOT NULL DEFAULT 'weekly',
    active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL, title TEXT NOT NULL, body TEXT, link TEXT, read_at TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS verification_requests (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL, evidence_url TEXT, note TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
    reviewed_by TEXT REFERENCES users(id) ON DELETE SET NULL, reviewed_at TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS reports (
    id TEXT PRIMARY KEY, reporter_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, reason TEXT NOT NULL, details TEXT,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','resolved','dismissed')),
    resolved_by TEXT REFERENCES users(id) ON DELETE SET NULL, resolved_at TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS talent_shortlists (
    employer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    candidate_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    note TEXT, created_at TEXT NOT NULL, PRIMARY KEY(employer_id, candidate_id)
  );
  CREATE TABLE IF NOT EXISTS application_events (
    id TEXT PRIMARY KEY, application_id TEXT NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    actor_id TEXT REFERENCES users(id) ON DELETE SET NULL, event_type TEXT NOT NULL,
    from_status TEXT, to_status TEXT, note TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS career_resources (
    id TEXT PRIMARY KEY, title TEXT NOT NULL, category TEXT NOT NULL, description TEXT NOT NULL,
    url TEXT, status TEXT NOT NULL DEFAULT 'published', created_at TEXT NOT NULL
  );
  `);

  // Backwards-compatible, additive job/domain migration.
  addColumn(db, 'jobs', "opportunity_kind TEXT NOT NULL DEFAULT 'job'");
  addColumn(db, 'jobs', "function_area TEXT");
  addColumn(db, 'jobs', "workplace TEXT NOT NULL DEFAULT 'onsite'");
  addColumn(db, 'jobs', "compensation_min INTEGER");
  addColumn(db, 'jobs', "compensation_max INTEGER");
  addColumn(db, 'jobs', "currency TEXT NOT NULL DEFAULT 'INR'");
  addColumn(db, 'jobs', "compensation_period TEXT");
  addColumn(db, 'jobs', "paid INTEGER NOT NULL DEFAULT 1");
  addColumn(db, 'jobs', "application_deadline TEXT");
  addColumn(db, 'jobs', "start_date TEXT");
  addColumn(db, 'jobs', "duration TEXT");
  addColumn(db, 'jobs', "languages_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'jobs', "portfolio_required INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'jobs', "slots INTEGER NOT NULL DEFAULT 1");
  addColumn(db, 'jobs', "moderation_note TEXT");
  addColumn(db, 'jobs', "published_at TEXT");
  addColumn(db, 'profiles', "availability TEXT");
  addColumn(db, 'profiles', "languages_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'profiles', "credits_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'profiles', "open_to_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'profiles', "day_rate INTEGER");
  addColumn(db, 'profiles', "currency TEXT NOT NULL DEFAULT 'INR'");
  addColumn(db, 'users', "email_verified INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'users', "last_login_at TEXT");
  addColumn(db, 'profiles', "roles_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'profiles', "gear_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'profiles', "software_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'profiles', "years_experience INTEGER");
  addColumn(db, 'profiles', "travel_radius_km INTEGER");
  addColumn(db, 'profiles', "travels_nationally INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'profiles', "travels_internationally INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'profiles', "remote_recording INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'profiles', "sight_reading INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'profiles', "passport_ready INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'profiles', "hourly_rate INTEGER");
  addColumn(db, 'profiles', "session_rate INTEGER");
  addColumn(db, 'profiles', "show_rate INTEGER");
  addColumn(db, 'profiles', "tour_day_rate INTEGER");
  addColumn(db, 'portfolio_items', "tags_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'portfolio_items', "genres_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'portfolio_items', "roles_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'portfolio_items', "instruments_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'portfolio_items', "credited_as TEXT");
  addColumn(db, 'portfolio_items', "year INTEGER");
  addColumn(db, 'portfolio_items', "featured INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'portfolio_items', "thumbnail_url TEXT");
  addColumn(db, 'portfolio_items', "sort_order INTEGER NOT NULL DEFAULT 0");
  addColumn(db, 'portfolio_items', "visibility TEXT NOT NULL DEFAULT 'public'");
  addColumn(db, 'jobs', "screening_questions_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'applications', "screening_answers_json TEXT NOT NULL DEFAULT '[]'");
  addColumn(db, 'applications', "recruiter_rating INTEGER");
  addColumn(db, 'applications', "recruiter_note TEXT");

  db.exec(`
  CREATE TABLE IF NOT EXISTS acts (
    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, act_type TEXT NOT NULL, tagline TEXT, bio TEXT, city TEXT,
    genres_json TEXT NOT NULL DEFAULT '[]', languages_json TEXT NOT NULL DEFAULT '[]',
    event_types_json TEXT NOT NULL DEFAULT '[]', lineup_size INTEGER NOT NULL DEFAULT 1,
    min_fee INTEGER, max_fee INTEGER, currency TEXT NOT NULL DEFAULT 'INR', fee_basis TEXT NOT NULL DEFAULT 'event',
    travel_radius_km INTEGER, travels_nationally INTEGER NOT NULL DEFAULT 0, travels_internationally INTEGER NOT NULL DEFAULT 0,
    tech_rider_url TEXT, hospitality_rider_url TEXT, promo_url TEXT, verified INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('draft','active','paused','archived')),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS act_members (
    id TEXT PRIMARY KEY, act_id TEXT NOT NULL REFERENCES acts(id) ON DELETE CASCADE,
    user_id TEXT REFERENCES users(id) ON DELETE SET NULL, display_name TEXT NOT NULL,
    role_name TEXT NOT NULL, instrument TEXT, is_leader INTEGER NOT NULL DEFAULT 0,
    member_status TEXT NOT NULL DEFAULT 'confirmed' CHECK(member_status IN ('invited','confirmed','substitute','inactive')),
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS booking_requests (
    id TEXT PRIMARY KEY, act_id TEXT NOT NULL REFERENCES acts(id) ON DELETE CASCADE,
    requester_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL, event_name TEXT, event_date TEXT NOT NULL, start_time TEXT,
    duration_minutes INTEGER, venue_name TEXT, venue_address TEXT, city TEXT NOT NULL,
    audience_size INTEGER, indoor_outdoor TEXT, budget_min INTEGER, budget_max INTEGER,
    currency TEXT NOT NULL DEFAULT 'INR', requirements TEXT, production_provided_json TEXT NOT NULL DEFAULT '[]',
    travel_provided INTEGER NOT NULL DEFAULT 0, accommodation_provided INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'requested' CHECK(status IN ('requested','viewed','quoted','negotiating','accepted','declined','cancelled','completed','disputed')),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS booking_quotes (
    id TEXT PRIMARY KEY, booking_id TEXT NOT NULL REFERENCES booking_requests(id) ON DELETE CASCADE,
    created_by TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    performance_fee INTEGER NOT NULL, travel_fee INTEGER NOT NULL DEFAULT 0, production_fee INTEGER NOT NULL DEFAULT 0,
    other_fee INTEGER NOT NULL DEFAULT 0, currency TEXT NOT NULL DEFAULT 'INR', deposit_percent INTEGER NOT NULL DEFAULT 50,
    valid_until TEXT, inclusions TEXT, exclusions TEXT, cancellation_terms TEXT,
    status TEXT NOT NULL DEFAULT 'sent' CHECK(status IN ('draft','sent','accepted','rejected','expired','superseded')),
    created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS booking_events (
    id TEXT PRIMARY KEY, booking_id TEXT NOT NULL REFERENCES booking_requests(id) ON DELETE CASCADE,
    actor_id TEXT REFERENCES users(id) ON DELETE SET NULL, event_type TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS booking_payments (
    id TEXT PRIMARY KEY, booking_id TEXT NOT NULL REFERENCES booking_requests(id) ON DELETE CASCADE,
    quote_id TEXT REFERENCES booking_quotes(id) ON DELETE SET NULL, payer_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('deposit','balance','refund','adjustment')), amount INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'INR', provider TEXT NOT NULL DEFAULT 'internal', provider_order_id TEXT,
    provider_payment_id TEXT, status TEXT NOT NULL CHECK(status IN ('created','authorized','paid','failed','refunded','cancelled')),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS organizations (
    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, org_type TEXT, website TEXT, city TEXT, tax_id TEXT, billing_email TEXT,
    status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS organization_members (
    organization_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('owner','admin','recruiter','booker','finance','member')),
    created_at TEXT NOT NULL, PRIMARY KEY(organization_id,user_id)
  );
  CREATE TABLE IF NOT EXISTS subscriptions (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_code TEXT NOT NULL, provider TEXT NOT NULL DEFAULT 'internal', provider_subscription_id TEXT,
    status TEXT NOT NULL CHECK(status IN ('trialing','pending','active','past_due','paused','cancelled','expired')),
    trial_started_at TEXT, trial_ends_at TEXT, current_period_start TEXT, current_period_end TEXT,
    cancel_at_period_end INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS billing_events (
    id TEXT PRIMARY KEY, provider TEXT NOT NULL, provider_event_id TEXT, user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL, payload_json TEXT, processed_at TEXT NOT NULL,
    UNIQUE(provider,provider_event_id)
  );
  CREATE TABLE IF NOT EXISTS usage_counters (
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, metric TEXT NOT NULL, period_key TEXT NOT NULL,
    value INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, PRIMARY KEY(user_id,metric,period_key)
  );
  CREATE TABLE IF NOT EXISTS email_tokens (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL CHECK(purpose IN ('verify_email','reset_password')), token_hash TEXT NOT NULL UNIQUE,
    expires_at TEXT NOT NULL, used_at TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS availability_windows (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_at TEXT NOT NULL, end_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'available' CHECK(status IN ('available','hold','tentative','booked','unavailable')),
    city TEXT, note TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS urgent_requests (
    id TEXT PRIMARY KEY, requester_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL, role_name TEXT NOT NULL, instrument TEXT, city TEXT NOT NULL,
    start_at TEXT NOT NULL, end_at TEXT, budget_min INTEGER, budget_max INTEGER, currency TEXT NOT NULL DEFAULT 'INR',
    genre TEXT, requirements TEXT, travel_covered INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','filled','cancelled','expired')),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS urgent_request_responses (
    request_id TEXT NOT NULL REFERENCES urgent_requests(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT, rate INTEGER, status TEXT NOT NULL DEFAULT 'available' CHECK(status IN ('available','shortlisted','selected','declined','withdrawn')),
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(request_id,user_id)
  );
  CREATE TABLE IF NOT EXISTS talent_folders (
    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, description TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS talent_folder_members (
    folder_id TEXT NOT NULL REFERENCES talent_folders(id) ON DELETE CASCADE,
    candidate_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    note TEXT, created_at TEXT NOT NULL, PRIMARY KEY(folder_id,candidate_id)
  );
  CREATE TABLE IF NOT EXISTS band_projects (
    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL, concept TEXT, city TEXT, genres_json TEXT NOT NULL DEFAULT '[]',
    commitment_type TEXT, rehearsal_schedule TEXT, compensation_model TEXT, status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS band_project_roles (
    id TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES band_projects(id) ON DELETE CASCADE,
    role_name TEXT NOT NULL, instrument TEXT, count_needed INTEGER NOT NULL DEFAULT 1,
    skill_level TEXT, requirements TEXT, compensation TEXT, status TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL
  );
  `);

  addColumn(db, 'band_project_roles', "opportunity_id TEXT");

  db.exec(`
  CREATE TABLE IF NOT EXISTS recent_activity (
    id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK(kind IN ('search','profile_view','act_view','job_view')),
    query TEXT, entity_id TEXT, label TEXT, created_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS crew_plans (
    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title TEXT NOT NULL, event_type TEXT NOT NULL, city TEXT NOT NULL, event_date TEXT,
    audience_size INTEGER, budget INTEGER, currency TEXT NOT NULL DEFAULT 'INR', genres_json TEXT NOT NULL DEFAULT '[]',
    needs_json TEXT NOT NULL DEFAULT '[]', notes TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS crew_plan_roles (
    id TEXT PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES crew_plans(id) ON DELETE CASCADE,
    category TEXT NOT NULL, role_name TEXT NOT NULL, instrument TEXT, count_needed INTEGER NOT NULL DEFAULT 1,
    priority TEXT NOT NULL DEFAULT 'recommended', rationale TEXT, created_at TEXT NOT NULL
  );
  `);
  addColumn(db, 'portfolio_items', "media_metadata_json TEXT NOT NULL DEFAULT '{}'");
  addColumn(db, 'portfolio_items', "waveform_url TEXT");
  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_recent_activity_user_created ON recent_activity(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_crew_plans_owner_created ON crew_plans(owner_id,created_at DESC);
  `);

  db.exec(`
    CREATE INDEX IF NOT EXISTS idx_jobs_status_created ON jobs(status, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_jobs_kind_function ON jobs(opportunity_kind, function_area);
    CREATE INDEX IF NOT EXISTS idx_jobs_location ON jobs(location);
    CREATE INDEX IF NOT EXISTS idx_apps_candidate ON applications(candidate_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_apps_job ON applications(job_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, read_at, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_acts_status_city ON acts(status, city);
    CREATE INDEX IF NOT EXISTS idx_booking_act_date ON booking_requests(act_id, event_date);
    CREATE INDEX IF NOT EXISTS idx_booking_requester ON booking_requests(requester_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_booking_payments_booking ON booking_payments(booking_id, created_at DESC);
    CREATE UNIQUE INDEX IF NOT EXISTS idx_booking_provider_order ON booking_payments(provider, provider_order_id) WHERE provider_order_id IS NOT NULL;
    CREATE INDEX IF NOT EXISTS idx_subscriptions_user ON subscriptions(user_id, status);
    CREATE INDEX IF NOT EXISTS idx_band_projects_owner ON band_projects(owner_id, status);
    CREATE INDEX IF NOT EXISTS idx_availability_user_time ON availability_windows(user_id,start_at,end_at);
    CREATE INDEX IF NOT EXISTS idx_urgent_status_city ON urgent_requests(status,city,start_at);
    CREATE INDEX IF NOT EXISTS idx_urgent_responses_user ON urgent_request_responses(user_id,status);
    CREATE INDEX IF NOT EXISTS idx_talent_folders_owner ON talent_folders(owner_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_portfolio_user_featured ON portfolio_items(user_id,featured DESC,sort_order,created_at DESC);
  `);
}

function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  return { salt, hash: crypto.scryptSync(password, salt, 64).toString('hex') };
}

function seed(db) {
  const t = now();
  const ensureUser = (email, name, role, password, profile={}) => {
    let u = db.prepare('SELECT id FROM users WHERE email=?').get(email);
    if (u) return u.id;
    const id = uid('usr'); const {salt,hash}=hashPassword(password);
    db.prepare('INSERT INTO users(id,name,email,role,password_hash,password_salt,status,profile_complete,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run(id,name,email,role,hash,salt,'active',1,t,t);
    db.prepare(`INSERT INTO profiles(user_id,headline,bio,location,skills_json,genres_json,instruments_json,company_name,company_description,verified,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?)`).run(id,profile.headline||null,profile.bio||null,profile.location||null,JSON.stringify(profile.skills||[]),JSON.stringify(profile.genres||[]),JSON.stringify(profile.instruments||[]),profile.companyName||null,profile.companyDescription||null,profile.verified?1:0,t);
    return id;
  };
  const production=process.env.NODE_ENV==='production';
  const adminEmail=(process.env.ADMIN_EMAIL||'admin@verse.local').toLowerCase();
  const adminPassword=process.env.ADMIN_PASSWORD||'Admin@12345';
  if(production&&(!process.env.ADMIN_EMAIL||!process.env.ADMIN_PASSWORD||adminPassword.length<14)){
    throw new Error('Production requires ADMIN_EMAIL and an ADMIN_PASSWORD of at least 14 characters.');
  }
  ensureUser(adminEmail,'Verse Admin','admin',adminPassword);
  const seedDemo=process.env.SEED_DEMO_DATA==='true'||(!production&&process.env.SEED_DEMO_DATA!=='false');
  if(!seedDemo)return;
  const employerId=ensureUser('studio@verse.local','YRF Studios','employer','Employer@123',{companyName:'YRF Studios',companyDescription:'Film and music production studio',verified:true,location:'Mumbai, Maharashtra'});
  if(!db.prepare("SELECT 1 FROM subscriptions WHERE user_id=? AND status IN ('active','trialing')").get(employerId)){const sid=uid('sub');db.prepare('INSERT INTO subscriptions(id,user_id,plan_code,provider,status,current_period_start,current_period_end,cancel_at_period_end,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)').run(sid,employerId,'studio','internal','active',t,new Date(Date.now()+365*864e5).toISOString(),0,t,t);}
  ensureUser('artist@verse.local','Aditya Sharma','jobseeker','Artist@123',{headline:'Playback Singer',bio:'Versatile vocalist with studio and live experience.',location:'Mumbai, Maharashtra',skills:['Playback Singing','Studio Recording','Hindi'],genres:['Bollywood','Pop'],instruments:['Vocals']});
  if (db.prepare('SELECT COUNT(*) c FROM jobs').get().c===0) {
    const stmt=db.prepare(`INSERT INTO jobs(id,employer_id,title,company,location,type,genre,salary,description,requirements,skills_json,experience_level,status,featured,created_at,updated_at,opportunity_kind,function_area,workplace,compensation_min,compensation_max,currency,compensation_period,paid,portfolio_required,published_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
    const rows=[
      ['Playback Singer — Feature Film','Contract','Bollywood','₹2,00,000–₹5,00,000/song','Seeking an experienced playback singer for an upcoming Hindi film.','5+ years experience; strong studio discipline; Hindi diction',['Playback Singing','Studio Recording','Hindi'],'senior','audition','Performance','onsite',200000,500000,'INR','per song',1,1],
      ['Music Producer — Independent Albums','Full-time','Bollywood','₹8,00,000–₹15,00,000/year','Produce original music for film and independent releases.','Strong portfolio; DAW expertise; collaboration skills',['Music Production','Logic Pro','Mixing'],'senior','job','Production','hybrid',800000,1500000,'INR','year',1,1],
      ['Touring Guitarist — India Tour','Freelance','Pop','₹30,000–₹60,000/show','Touring guitarist required for national live shows.','Touring availability; live rig proficiency',['Guitar','Live Performance'],'intermediate','tour','Live & Touring','travel',30000,60000,'INR','show',1,1],
      ['Assistant Recording Engineer — Studio Sessions','Part-time','Multi-genre','₹1,500–₹3,000/session','Support recording sessions, patching, session setup and file management.','Basic Pro Tools; signal-flow fundamentals',['Pro Tools','Recording','Studio Operations'],'entry','session','Audio Engineering','onsite',1500,3000,'INR','session',1,0]
    ];
    for(const r of rows){const id=uid('job');stmt.run(id,employerId,r[0],'YRF Studios','Mumbai, Maharashtra',r[1],r[2],r[3],r[4],r[5],JSON.stringify(r[6]),r[7],'published',0,t,t,r[8],r[9],r[10],r[11],r[12],r[13],r[14],r[15],r[16],t);}
  }
  if (db.prepare('SELECT COUNT(*) c FROM career_resources').get().c===0) {
    const s=db.prepare('INSERT INTO career_resources VALUES(?,?,?,?,?,?,?)');
    [
      ['res_credits','How music credits actually work','Industry fundamentals','A practical guide to documenting releases, roles and contribution credits.','https://www.allmusic.com/','published',t],
      ['res_rights','Rights, royalties & metadata basics','Music business','Understand publishing, master rights, neighbouring rights and why metadata matters.','https://www.iprs.org/','published',t],
      ['res_portfolio','Build a hiring-ready music portfolio','Career','How to present credits, reels, session work and proof of execution for different roles.',null,'published',t]
    ].forEach(r=>s.run(...r));
  }
}
