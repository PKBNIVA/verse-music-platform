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
- S3/R2: access keys, bucket, endpoint, region, and public base URL

## Provider integration acceptance

The provider contract tests use fake transport responses; passing them verifies request
construction and error handling, not a live provider connection. Record the outcome
of each controlled test before declaring an integration operational.

| Provider | Railway environment names | Controlled verification |
| --- | --- | --- |
| Razorpay | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `RAZORPAY_PLAN_PRO`, `RAZORPAY_PLAN_STUDIO` | Configure live plans and the webhook URL `https://verse-music-platform-production.up.railway.app/api/billing/webhook/razorpay`. Complete a controlled checkout, authenticated webhook, cancellation, and reconciliation check. Keep test and live credentials separate. |
| Brevo | `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME` | Verify the sending domain and sender in Brevo, then deliver a verification and reset email to controlled addresses. Check provider acceptance, inbox receipt, bounce status, and the resulting links. |
| S3-compatible storage | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_BUCKET`, `AWS_ENDPOINT_URL_S3`, `AWS_PUBLIC_BASE_URL` | Upload, read, and delete a controlled image and audio file through the browser. Verify object durability, access policy, MIME/size rejection, CORS, and cleanup. |

Keep credentials in Railway's secret settings, not in the repository or frontend
`VITE_` variables. The public Razorpay Key ID is returned by the API only for checkout;
its Key Secret and webhook secret must stay server-side. Vercel needs the public
`VITE_API_URL` and `VITE_PUBLIC_URL` values documented above. If provider credentials
are absent, report the corresponding flow as disabled or unverified.

When Razorpay is not configured, production payment creation must fail closed; it must
never silently use mock checkout.

## Release gate

Every release must pass:

```bash
npm ci
npm run build
npm run test:all
npm run qa:e2e
cd backend
bundle install
bin/rails db:prepare
bin/rails test
bin/rails zeitwerk:check
```

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
