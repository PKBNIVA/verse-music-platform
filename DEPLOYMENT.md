# Verse production deployment

## Source of truth

Production is the Rails/Vite application on the GitHub `production` branch.

- Frontend: Vercel
- API and GoodJob workers: Railway
- Database: Railway PostgreSQL
- Object storage: S3-compatible storage when configured
- Payments: Razorpay when live credentials are configured
- Transactional email: Brevo when live credentials are configured

The divergent legacy Node/Render application on `main` is not a release source. Do not
connect a production provider to `main`.

## Frontend — Vercel

Configure the repository root as a Vite project:

- Production branch: `production`
- Build command: `npm run build`
- Output directory: `dist`
- `VITE_API_URL=https://verse-music-platform-production.up.railway.app/api`
- `VITE_PUBLIC_URL=https://verse-music-platform.vercel.app`

`vercel.json` provides SPA routing, immutable asset caching, and browser security headers.

## API — Railway

Configure one service from `backend/Dockerfile`:

- Production branch: `production`
- Config file: `railway.toml`
- PostgreSQL must expose `DATABASE_URL` to the Rails service.
- The container runs `db:prepare` before Puma.
- Railway's liveness probe is `/api/live`.
- Operational checks are `/api/health` and `/api/readiness`.

GoodJob initially runs inside the web service with
`GOOD_JOB_EXECUTION_MODE=async`, `GOOD_JOB_MAX_THREADS=2`, and
`GOOD_JOB_ENABLE_CRON=true`. Run cron on exactly one process. Move to a separate worker
with `bundle exec good_job start` and `GOOD_JOB_EXECUTION_MODE=external` when queue
volume or web latency justifies it.

## Required launch configuration

Set strong, provider-managed secrets. Never commit values.

- `SECRET_KEY_BASE`
- `DATABASE_URL`
- `FRONTEND_URL`, `FRONTEND_HOST`, and `ALLOWED_ORIGINS`
- `API_HOST`
- `ADMIN_EMAIL` and `ADMIN_PASSWORD`
- GoodJob variables from `.env.example`

Before enabling each integration, configure and test its variables:

- Razorpay: key ID, key secret, webhook secret, and plan IDs
- Brevo: API key and verified sender

### Email sign-in codes and `PASSWORD_LOGIN_ENABLED`

Email sign-in codes are the primary sign-in path; password sign-in stays available as a
fallback. `PASSWORD_LOGIN_ENABLED` defaults to `true`. Set it to `false` only after a
controlled production test shows sign-in codes reaching real inboxes (Brevo acceptance
is not enough); otherwise every user is locked out. When `false`, `POST /api/auth/login`
returns 403 `PASSWORD_LOGIN_DISABLED` (admins included) while `/api/auth/otp/request`
and `/api/auth/otp/verify` keep working. Roll back by setting it to `true` again.
Codes expire after 10 minutes, are single use, allow 5 attempts, and are limited to 5
requests per email and per IP per hour. Outside production, and only when no email
provider is configured, the request response includes `debugCode` for local QA.
- S3/R2: access keys, bucket, endpoint, region, and public base URL

## Provider integration acceptance

The provider contract tests use fake transport responses; passing them verifies request
construction and error handling, not a live provider connection. Record the outcome
of each controlled test before declaring an integration operational.

| Provider | Railway environment names | Controlled verification |
| --- | --- | --- |
| Razorpay | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `RAZORPAY_PLAN_PRO`, `RAZORPAY_PLAN_STUDIO` | Follow the **Payments (Razorpay) go-live checklist** below: dashboard field mapping, webhook URL `https://verse-music-platform-production.up.railway.app/api/billing/webhook/razorpay` and events, automatic capture, test-mode rehearsal, then live switch. Keep test and live credentials separate. |
| Brevo | `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME` | Verify the sending domain and sender in Brevo, then deliver a verification and reset email to controlled addresses. Check provider acceptance, inbox receipt, bounce status, and the resulting links. |
| S3-compatible storage | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_BUCKET`, `AWS_ENDPOINT_URL_S3`, `AWS_PUBLIC_BASE_URL`, optional `AWS_UPLOAD_METHOD` (see "Object storage — Cloudflare R2") | Upload, read, and delete a controlled image and audio file through the browser. Verify object durability, access policy, MIME/size rejection, CORS, and cleanup. |

Keep credentials in Railway's secret settings, not in the repository or frontend
`VITE_` variables. The public Razorpay Key ID is returned by the API only for checkout;
its Key Secret and webhook secret must stay server-side. Vercel needs the public
`VITE_API_URL` and `VITE_PUBLIC_URL` values documented above. If provider credentials
are absent, report the corresponding flow as disabled or unverified.

When Razorpay is not configured, production payment creation must fail closed; it must
never silently use mock checkout.

## Object storage — Cloudflare R2

Without `AWS_BUCKET`, production uploads return 503 unless `PERSISTENT_UPLOADS=true` with a
Railway volume, which pins the API to one replica. R2 removes that limit.

How uploads work: `POST /api/uploads/presign` records a pending `uploads` row and returns
browser upload instructions; the browser sends the file straight to the bucket; then
`POST /api/uploads/:id/complete` reads the object's size and first bytes and deletes it if
either does not match. Work samples accept only external HTTPS links or the user's own
completed uploads. Deleting a work sample deletes its file; the daily `upload_sweep` cron
(04:43 UTC) deletes pending uploads older than 24 h, completed uploads no work sample uses,
uploads whose owner was deleted, and untracked `uploads/` objects that no work sample links to.

Upload method: `AWS_UPLOAD_METHOD=post` uses a presigned POST policy (exact size, exact
Content-Type, fixed key). R2 does not document POST-policy uploads, so an
`*.r2.cloudflarestorage.com` endpoint defaults to `put`: a presigned PUT whose Content-Type
and Content-Length are signed. Both are re-verified by `complete`. Only set `post` for R2
after a controlled upload succeeds with it.

Checklist:

1. **Bucket.** Cloudflare dashboard → R2 → Create bucket, e.g. `verse-uploads` (location:
   automatic or closest to users; default storage class). Keep the bucket private to the S3
   API; public reads go through step 3.
2. **API token.** R2 → Manage API tokens → Create API token: permission *Object Read & Write*,
   scoped to `verse-uploads` only, no expiry or a tracked expiry. Record the Access Key ID,
   Secret Access Key and the account's S3 endpoint
   `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`.
3. **Public reads.** Bucket → Settings → Custom Domains → connect e.g. `media.<your-domain>`
   (the zone must be on Cloudflare). For a trial only, enable the `r2.dev` subdomain instead;
   it is rate-limited and not meant for production.
4. **CORS.** Bucket → Settings → CORS policy:

   ```json
   [
     {
       "AllowedOrigins": ["https://verse-music-platform.vercel.app"],
       "AllowedMethods": ["PUT", "POST", "GET", "HEAD"],
       "AllowedHeaders": ["content-type"],
       "ExposeHeaders": ["ETag"],
       "MaxAgeSeconds": 3600
     }
   ]
   ```

   Add any other production frontend origin (custom domain) to `AllowedOrigins`; never `*`.
5. **Railway variables** (API service, secret settings):

   | Variable | Value |
   | --- | --- |
   | `AWS_ACCESS_KEY_ID` | R2 token Access Key ID |
   | `AWS_SECRET_ACCESS_KEY` | R2 token Secret Access Key |
   | `AWS_REGION` | `auto` |
   | `AWS_BUCKET` | `verse-uploads` |
   | `AWS_ENDPOINT_URL_S3` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
   | `AWS_PUBLIC_BASE_URL` | `https://media.<your-domain>` (or the `https://pub-….r2.dev` URL) |
   | `AWS_UPLOAD_METHOD` | leave unset (→ `put` on R2) |

   `AWS_PUBLIC_BASE_URL` is mandatory with a custom endpoint; without it uploads return 503
   `STORAGE_MISCONFIGURED`. Nothing storage-related goes into Vercel `VITE_` variables.
6. **CSP.** `vercel.json` already allows `connect-src https://*.r2.cloudflarestorage.com`
   (browser upload) and `img-src`/`media-src https:` (playback). PDFs open in a new tab, so no
   `frame-src` change is needed.
7. **Verify.** `GET /api/admin/health` → `checks.storage.ok: true`, `uploadMethod: "put"` and
   no `problems` (codes such as `missing_credentials`, `missing_public_base_url`,
   `insecure_endpoint`; values are never echoed). The admin tester's "Upload storage" check
   shows the same. Then, in the browser, upload an image, an MP3 and a PDF on
   `/jobseeker/portfolio`, play them, confirm a renamed `.txt → .png` is rejected, delete each
   sample and confirm the object is gone from the bucket.
8. **After migrating.** Remove `PERSISTENT_UPLOADS` and the volume only after existing
   `/rails/active_storage/...` work samples have been re-uploaded or accepted as lost; the
   Disk files live only on that volume.

## Payments (Razorpay) go-live checklist

Owner steps, in order. Nothing here is automated; tick each item and record the date.

### 1. Railway variables ← Razorpay dashboard

Set these on the Railway **API service** (production environment). Never in Vercel.

| Railway variable | Razorpay dashboard field (Live mode unless stated) |
| --- | --- |
| `RAZORPAY_KEY_ID` | Account & Settings → API Keys → **Key Id** (`rzp_live_…`) |
| `RAZORPAY_KEY_SECRET` | Account & Settings → API Keys → **Key Secret** (shown once when the key is generated; regenerate if lost) |
| `RAZORPAY_WEBHOOK_SECRET` | Account & Settings → Webhooks → your webhook → **Secret** (you choose it; use `openssl rand -hex 32`) |
| `RAZORPAY_PLAN_PRO` | Subscriptions → Plans → the Pro plan's **Plan ID** (`plan_…`): Monthly, every 1 month, **INR 2,499.00** |
| `RAZORPAY_PLAN_STUDIO` | Subscriptions → Plans → the Studio plan's **Plan ID**: Monthly, every 1 month, **INR 5,999.00** |
| `RAZORPAY_ALLOW_TEST_MODE` | not a dashboard field: set `true` **only** during the test-mode rehearsal below, then delete |
| `RAZORPAY_SIMULATOR` | must **not** exist on Railway (it is ignored in production and `GET /api/admin/health` reports `checks.payments.ok: false` if present) |

The plan amounts must match `Billing::BillingController::PLANS` (the server sends only the
plan id; Razorpay charges what the plan says). Test-mode and live-mode keys, plans and
webhooks are separate objects in Razorpay: create each in both modes.

### 2. Webhook

Account & Settings → Webhooks → Add New Webhook (in each mode):

- Webhook URL: `https://verse-music-platform-production.up.railway.app/api/billing/webhook/razorpay`
- Secret: the value of `RAZORPAY_WEBHOOK_SECRET`
- Active events: `subscription.authenticated`, `subscription.activated`, `subscription.charged`,
  `subscription.pending`, `subscription.halted`, `subscription.paused`, `subscription.resumed`,
  `subscription.cancelled`, `subscription.completed`, `payment.captured`, `payment.failed`,
  `refund.processed`. (Other events are recorded and ignored.)

### 3. Payment capture

Account & Settings → Payment Capture → **Automatic capture** (immediate). Deposit
confirmation requires a `captured` payment; an authorised-but-uncaptured payment is refused
and Razorpay auto-refunds it later.

### 4. Test-mode rehearsal on Railway (before any live key)

1. Set the test-mode `rzp_test_` key id/secret, test-mode plan ids, the test-mode webhook
   secret, and `RAZORPAY_ALLOW_TEST_MODE=true`. Redeploy.
2. `GET /api/admin/health` → `checks.payments.ok` is true with `mode: "test"`, and the Billing page shows
   the **Test mode** banner.
3. As a throwaway employer: Billing → Pro → Start free trial → complete checkout with a
   Razorpay test card that supports recurring payments. The page moves to **Free trial**
   within seconds; Admin → `GET /api/admin/billing-events` shows `subscription.authenticated`
   with `processingResult: applied`.
4. Cancel from the Billing page (trial cancellation is immediate) and confirm the Razorpay
   dashboard shows the subscription cancelled.
5. Booking deposit: accept a quote, pay the deposit with a test card → **Deposit paid ·
   booking confirmed**; repeat with a failing test card → decline message and retry works.
6. Refund that deposit from the Razorpay dashboard → `refund.processed` arrives and the
   booking shows **Deposit refunded**.
7. `GET /api/admin/billing-attempts` has no `pending`/`ambiguous` rows older than 30 minutes.

### 5. Go live

Replace the four Razorpay values with live-mode ones, **delete** `RAZORPAY_ALLOW_TEST_MODE`,
redeploy, confirm the Test mode banner is gone, then make one real low-value deposit on a
controlled booking and refund it from the dashboard. Record the outcome here.

### Local rehearsal without credentials (Razorpay simulator)

`RAZORPAY_SIMULATOR=true` with any `rzp_test_` key makes the API answer Razorpay calls from
`RazorpaySimulator` (in-process, no network) and replaces checkout.js with a simulated modal
(success / decline / close) whose handler payload is signed server-side. It is refused in
production and with live keys; its dev endpoints (`/api/dev/razorpay/*`: checkout,
`subscriptions/:id/{activate,charge,pending,halt,pause,resume,cancel,complete}`,
`payments/:id/refund`, `webhooks`) are not routed there. Simulator state is in memory:
restarting the API or reloading code clears it.

```bash
RAZORPAY_SIMULATOR=true RAZORPAY_KEY_ID=rzp_test_simulator RAZORPAY_KEY_SECRET=local_sim_secret \
RAZORPAY_WEBHOOK_SECRET=local_sim_webhook RAZORPAY_PLAN_PRO=plan_SimPro RAZORPAY_PLAN_STUDIO=plan_SimStudio \
  bin/rails server -p 3000            # in backend/, development env
QA_PAYMENTS_SIMULATOR=true QA_API_BASE_URL=http://127.0.0.1:3000/api npx playwright test tests/e2e/payments-simulator.spec.ts
```

The same flows run in `backend/test/integration/razorpay_simulator_flows_test.rb` on every
`bin/rails test`.

## Release gate

Every release must pass:

```bash
npm ci
npm audit --omit=dev --audit-level=high
npm run build
npm run test:all
npm run qa:e2e
cd backend
bundle install
bin/rails db:prepare
bin/rails test
bin/rails zeitwerk:check
bundle exec brakeman --no-pager --exit-on-warn
bundle exec bundler-audit check --update
```

CI (`.github/workflows/rails-and-web.yml`) runs these as the `frontend`, `rails`, `security`
and `integrated-journeys` jobs. The `rails` job also migrates an empty database and fails if
`backend/db/schema.rb` differs from the committed file. `npm run test:all` runs only the
frontend source smoke tests; the legacy Node server and its tests were removed.

The Railway image (`backend/Dockerfile`, build context = repository root) installs exactly the
gems in `backend/Gemfile.lock` with the Bundler version recorded there, in frozen deployment
mode. Build-context ignore rules are in `backend/Dockerfile.dockerignore`. Production never
rewrites `db/schema.rb` (`dump_schema_after_migration = false`).

The `integrated-journeys` CI job also builds the Vite frontend against a Rails server
and disposable PostgreSQL test database. It exercises both account roles through
registration, profile saving, logout, login, and server-side admin denial. It uses
reserved `example.invalid` addresses and never calls production providers. The
regular public-page browser checks use local API fixtures; their success alone does
not verify the Rails integration.

After deployment verify:

1. `/api/live`, `/api/health`, and `/api/readiness`.
2. Registration, verification, login, logout, and session expiry.
3. Candidate discovery, save, application, messaging, and availability.
4. Employer posting, application review, workspace, booking, and notifications.
5. Admin moderation and audit logging.
6. One controlled payment, webhook, refund, and reconciliation cycle after Razorpay is live
   (steps in the Payments go-live checklist).
7. One real transactional email after Brevo is live.
8. One upload/read/delete lifecycle after object storage is live.

## Error alerting and uptime

Error tracking is built in but **inert until a DSN is set**: with no DSN the API never
initialises Sentry and the web app never downloads it (zero requests to Sentry).

### 1. Create the Sentry projects (one time)

1. Sign up at sentry.io (the free Developer plan is enough to start) and create an
   organisation, e.g. `verse`. Pick the data region you prefer (US or EU); the CSP in
   `vercel.json` already allows `*.ingest.sentry.io`, `*.ingest.us.sentry.io` and
   `*.ingest.de.sentry.io`.
2. Create two projects:
   - `verse-api`, platform **Rails**;
   - `verse-web`, platform **React**.
3. Copy each project's DSN (Project settings → Client Keys (DSN)). A DSN is not a secret in
   the browser, but keep it out of the repository anyway.

### 2. Where each value goes

| Where | Variable | Value |
| --- | --- | --- |
| Railway (Rails service) | `SENTRY_DSN` | `verse-api` DSN |
| Railway | `SENTRY_ENVIRONMENT` | optional, defaults to `RAILS_ENV` (`production`) |
| Railway | `SENTRY_TRACES_SAMPLE_RATE` | optional, default `0` (errors only). `0.05` samples 5% of requests for performance data |
| Vercel (Production environment) | `VITE_SENTRY_DSN` | `verse-web` DSN |
| Vercel (Production environment) | `VITE_SENTRY_ENVIRONMENT` | `production` (Preview deployments can use `preview`, or leave the DSN unset there) |
| Vercel | `VITE_SENTRY_TRACES_SAMPLE_RATE` | optional, default `0` |

Releases are automatic: the API reports `RAILWAY_GIT_COMMIT_SHA` and the web build uses
`VERCEL_GIT_COMMIT_SHA` (exposed as `<meta name="verse-release">`). `VITE_*` values are read
at build time, so **redeploy Vercel after changing them**. Railway restarts on variable changes.

What is sent, and what is not:

- API: unhandled exceptions (500s), rescued errors that still answer 5xx (e.g. Razorpay
  gateway failures), errors the code swallows and logs (email enqueue/delivery, notification
  email, demo data jobs, upload sweep, billing reconciliation, checkout cleanup), GoodJob
  failures (discarded or retries exhausted — job class and job id only, never arguments),
  and GoodJob internal thread errors. Expected 4xx errors (not found, validation, bad
  request, routing) are never sent.
- Web: render crashes (app error boundary and route error page; a stale-chunk error only
  after the one automatic reload has failed), unhandled errors and promise rejections, and
  API 5xx/timeout/network failures rate-limited to one per kind per 5 minutes and at most 5
  per page session. API 4xx responses are never sent. Session replay is off.
- Privacy: no request bodies, cookies, query strings, IP addresses or job arguments; emails
  (also URL-encoded), bearer tokens, the `verse_access_token` value, `Authorization`/cookie
  headers and password/token/code/otp/secret/signature/body fields are scrubbed before
  sending. Users are identified by internal id and role only.

### 3. Alert rules (Sentry → Alerts → Create alert → Issues), for each project

1. **New issue** — "A new issue is created" → email the owner (and the team, if any).
2. **Spike** — "Number of events in an issue is more than 20 in 5 minutes" → email.
3. **Regression** — "The issue changes state from resolved to unresolved" → email.

Also enable Settings → Account → Notifications → "Workflow" and "Issue alerts" email, and
install the Sentry mobile app if you want push alerts.

### 4. Cost

The free Developer plan includes a fixed monthly error quota (about 5k errors at the time of
writing) and one user; check sentry.io/pricing for current limits. To stay inside it:
tracing defaults to 0, replay is off, API failure bursts in the browser are rate limited, and
expected 4xx are dropped. Set a spike-protection/quota limit per project in Sentry
(Settings → Subscription/Spend) so a bad deploy cannot exhaust the month. Raise
`SENTRY_TRACES_SAMPLE_RATE` / `VITE_SENTRY_TRACES_SAMPLE_RATE` only deliberately.

### 5. Verify after setting the DSNs

1. Sign in as an admin and open `/admin/tester` → **Error alerting**.
2. **Send server test error** calls `POST /api/admin/health/sentry-test` (admin only,
   audited as `admin.sentry_test`). It answers `captured: true` with an event id when
   `SENTRY_DSN` is set, `captured: false` when it is not. The event appears in `verse-api`
   as `Admin::HealthController::SentryTestError`, tagged `verse_test=true`.
3. **Send test error** (shown only when the build has `VITE_SENTRY_DSN`) sends a tagged client
   error to `verse-web`.
4. Confirm the "new issue" alert emails arrive, then resolve both test issues.

### 6. Uptime monitoring (free)

Use UptimeRobot (free: 50 monitors, 5-minute interval) or Better Stack Uptime (free tier):

| Monitor | URL | Check |
| --- | --- | --- |
| Verse API | `https://verse-music-platform-production.up.railway.app/api/health` | HTTP 200, keyword `"ok":true` |
| Verse web | `https://verse-music-platform.vercel.app` | HTTP 200 |

Interval 5 minutes, alert contact = owner email, alert after 2 consecutive failures to avoid
noise from a single cold start. (`/api/readiness` answers 503 while a core dependency is down;
add it as a third monitor if you want database outages to page separately.)

### 7. Deploy verification without opening Railway

After merging to `production`, run **Actions → Verse QA Agent → Run workflow** on the
`production` branch. For manual runs the live job sets `QA_EXPECTED_RELEASE` to the
workflow's commit, and `tests/e2e/api-health.spec.ts` polls for up to 5 minutes until
`GET /api/health` reports that commit (first 12 characters) and the web app's
`<meta name="verse-release">` matches it. A red run means Railway or Vercel did not deploy
that commit. Scheduled runs skip this check because they may legitimately test an older
deploy. `window.__VERSE_RELEASE__` in the browser console shows the running web build.

## Backups and rollback

Railway's current trial does not provide managed backups or point-in-time recovery.
Production launch requires a paid backup/PITR plan or an independently scheduled,
encrypted, off-platform PostgreSQL backup with a tested restore procedure.

Rollback application code by redeploying the last known-good `production` commit.
Database migrations must remain backward-compatible with the previous application release.

## Reversible synthetic QA batches

Synthetic batches use reserved `example.invalid` addresses and are tagged in
`users.synthetic_batch`. They never create an admin account, send registration email,
or call a real payment provider.

```bash
cd backend
BATCH=qa-YYYY-MM-DD JOBSEEKERS=225 EMPLOYERS=75 bin/rails synthetic_qa:seed
bin/rails synthetic_qa:list
BATCH=qa-YYYY-MM-DD bin/rails synthetic_qa:purge
```

Production additionally requires temporary `ALLOW_SYNTHETIC_QA=true` and
`SYNTHETIC_QA_PASSWORD`. Take a verified backup first, start with a small canary batch,
purge it, then run the full batch. Remove temporary variables immediately afterward.
Purge is transactional and idempotent.
