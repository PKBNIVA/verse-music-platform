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
| Razorpay | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `RAZORPAY_PLAN_PRO`, `RAZORPAY_PLAN_STUDIO` | Configure live plans and the webhook URL `https://verse-music-platform-production.up.railway.app/api/billing/webhook/razorpay`. Complete a controlled checkout, authenticated webhook, cancellation, and reconciliation check. Keep test and live credentials separate. |
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
6. One controlled payment, webhook, refund, and reconciliation cycle after Razorpay is live.
7. One real transactional email after Brevo is live.
8. One upload/read/delete lifecycle after object storage is live.

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
