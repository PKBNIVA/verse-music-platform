# Verse production audit — phase 1 (read-only)

Audit date: 2026-09-26. Audited commit: `production` @ `bf5acc6f38e321af99ea8fd5a7b68341c09e80ba`
(PRs #31–#34 merged after the #30 alignment commit `753b4c0`). No code, settings or data
were changed during this audit.

Labels: **R** reproduced locally · **V** verified in code · **I** inferred · **B** blocked by missing access.

## Evidence summary

- GitHub default branch `production`; no open PRs; `production` is **not branch-protected**.
- CI on `bf5acc6`: Rails and Web CI ✅, Verse QA Agent ✅. PR #34 checks: frontend, rails,
  integrated-journeys, local-experience, Vercel Preview Comments. No Railway check observed.
- Scheduled live QA (run 36230146312, 2026-09-26 08:34 UTC): 66 passed / 4 skipped;
  `/api/health` 200 ×5 within 2 s p95. The readiness test accepts 503, so live readiness is
  unverified. The live job performs GET requests only.
- Local: Rails 67 runs / 625 assertions / 0 failures; `zeitwerk:check` OK; `npm run build` OK;
  `npm audit --omit=dev` 0 vulnerabilities.
- `npm run test:all` (CI "frontend" job) tests the **legacy Node/SQLite server in `server/`**, not Rails.
- Not accessible from the audit sandbox: live site/API (egress policy), Vercel, Railway,
  production PostgreSQL, backup file, Razorpay, Brevo, object storage.

## Gap register

### P0
- **P0-1 (B)** No verified restorable production backup. DEPLOYMENT.md states the Railway trial
  has no managed backups/PITR; a single manual dump on the DB volume is not a backup. Verify
  checksum, restore into a scratch DB, then schedule encrypted off-platform dumps or buy PITR.

### P1
- **P1-1 (R)** Eight pages use `useEffect(load, [])` where `load` returns a Promise; React calls the
  Promise as the effect cleanup on unmount → "Unexpected Application Error: r is not a function".
  Pages: Bookings, SavedJobs, Portfolio, ApplicationTracking, JobDetails, EmployerDashboard,
  EmployerApplications, JobAlerts (`src/app/pages/*`). Reproduced on the production build;
  control pages unaffected.
- **P1-2 (R)** Admin verification approval and report resolution always raise
  `ActiveModel::UnknownAttributeError` (`reviewed_by:`/`resolved_by:` vs `*_id` columns) in
  `backend/app/controllers/admin/verifications_controller.rb` and `admin/reports_controller.rb`.
- **P1-3 (R)** `verification_requests.evidence_url` is NOT NULL (and `kind` defaults to
  `"pending"`) in `20260918000000_create_verse_schema.rb:126`; a request without evidence returns 500.
- **P1-4 (V/I)** Sign-in reliability (real-user complaint not yet reproduced):
  login form enforces `minLength={10}` (`AuthPage.tsx:50`); login throttle keyed by IP only, counts
  successes, memory_store, no `trusted_proxies` (`application_controller.rb:90`); token in
  `sessionStorage` (per tab) with a 5-session cap (`auth_controller.rb:87`); any `/me` failure
  clears the token (`authContext.tsx`); blocked storage throws before `try` (`api.ts:94`).
- **P1-5 (V)** CSP in `vercel.json`: `frame-src` allows only Razorpay (blocks YouTube/Spotify/
  SoundCloud work samples); `connect-src` omits the object-storage origin (uploads fail once
  `AWS_BUCKET` is set).

### P2
- CI tests the legacy Node server; no E2E coverage for apply, messaging, bookings, billing,
  uploads, admin.
- `Gemfile.lock` and `db/schema.rb` not committed; no Brakeman/bundler-audit.
- `db:prepare` on every container boot; persistent volume forces a single replica.
- DB pool 5 shared by Puma (5) and in-process GoodJob; no `statement_timeout`.
- Razorpay: no live/test key-mode guard; no frontend idempotency key (double subscriptions);
  plan change cancels the paid plan before the new one activates; unhandled
  completed/paused/resumed/payment.failed/refund events; reconciliation not scheduled and cannot
  resolve attempts without a provider id; shortlist/booking limits not enforced.
- Email: synchronous (≤15 s) with no retry, delivery log, or bounce/complaint webhook;
  forgot-password always reports success; `FRONTEND_URL` falls back to localhost.
- Uploads: presigned PUT does not enforce size; client-declared MIME; no object cleanup;
  R2 URLs wrong without `AWS_PUBLIC_BASE_URL`.
- Authorization: act owners can add any user; org admins can assign arbitrary roles incl.
  owner; folders expose hidden profiles; unrestricted messaging without rate limits.
- No account deletion or data export; `user.destroy` fails on RESTRICT foreign keys.
- Search is `ILIKE '%q%'` across OR'd columns (sequential scans); `applications.size` N+1;
  several unbounded lists.
- No error tracking, metrics or job-failure alerting.
- Job-alert notifications link to `/jobs/:id` (404); drafts cannot be edited/published; router
  has no `errorElement`.
- `production` unprotected; `npm run dev` proxies to the legacy Node port; `heroku.yml` divergent.

### P3/P4
Mixed snake/camel API casing; `window.prompt` workflows; ~46 unlinked labels; ~24 buttons
nested in links; ~25 unused dependencies; motion ignores reduced-motion; `verse_return_to` never
read; emails and Razorpay signatures not filtered from logs; `fitScore` never shown.

## Proposed first work package

Branch `claude/fix-unmount-crash-admin-500s`: fix P1-1 (8 one-line effect fixes) and P1-2
(`reviewed_by_id`/`resolved_by_id` + optional `belongs_to`), with a Playwright navigate-away
regression spec and Rails integration tests for admin verification/report updates. No migration,
no API contract change. P1-3 follows in its own PR with a reviewed, reversible migration.

## Access checklist (tokens live in environment settings, never in chat or the repo)

| Variable | Source | Scope |
| --- | --- | --- |
| `DATABASE_READONLY_URL` | Railway Postgres, dedicated read-only role | SELECT only |
| `RAILWAY_TOKEN` | Railway project token (production environment) | project |
| `VERCEL_TOKEN` | Vercel account token scoped to the team, with expiry | team |
| `RAZORPAY_TEST_KEY_ID`, `RAZORPAY_TEST_KEY_SECRET` | Razorpay Test mode API keys | test only |
| `BREVO_AUDIT_API_KEY` | Separate Brevo API key named "audit" | revoke after email work |
| `CLOUDFLARE_API_TOKEN` | Cloudflare custom token: Zone DNS read, R2 read | read |

Allowed egress hosts needed: `verse-music-platform.vercel.app`, `api.vercel.com`,
`verse-music-platform-production.up.railway.app`, `backboard.railway.com`, the Railway Postgres
TCP proxy host, `api.razorpay.com`, `api.brevo.com`, `api.cloudflare.com`.
Setup script addition: `npm i -g @railway/cli vercel`.
