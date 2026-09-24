# Verse deployment: Vercel + Railway now, Heroku later

## Frontend — Vercel

- Import this GitHub repository.
- Framework preset: Vite.
- Build command: `npm run build`.
- Output directory: `dist`.
- Add `VITE_API_URL=https://<railway-service>.up.railway.app/api`.
- Add `VITE_PUBLIC_URL=https://<vercel-project>.vercel.app` and replace the example hostname in `public/robots.txt` and `public/sitemap.xml` if Vercel assigns a different domain.

`vercel.json` includes SPA routing and security/cache headers.

## Backend — Railway (initial)

- Create a Railway project from this GitHub repository.
- Railway reads `railway.toml` and builds `backend/Dockerfile`.
- Add PostgreSQL and expose its `DATABASE_URL` to the Rails service.
- Configure the variables in `.env.example`; use the Railway-generated public domain for `API_HOST` and the Vercel domain for `FRONTEND_URL`, `FRONTEND_HOST`, and `ALLOWED_ORIGINS`.
- The container runs `db:prepare` before Puma and Railway checks `/api/health`.
- Durable jobs use GoodJob in the same PostgreSQL database. Set `GOOD_JOB_EXECUTION_MODE=async`, `GOOD_JOB_MAX_THREADS=2`, and `GOOD_JOB_ENABLE_CRON=true`; no Redis or second Railway service is required for the initial low-volume deployment.
- Verify `/api/readiness` reports `backgroundJobs.ok=true`, `adapter=good_job`, and `schemaReady=true`. The 15-minute job-alert sweep creates deduplicated in-app notifications for daily and weekly alerts. Alerts with frequency `saved` are stored filters and are not delivered.
- When queue volume grows, provision a worker from the same image with command `bundle exec good_job start`, change the web service to `GOOD_JOB_EXECUTION_MODE=external`, and leave cron enabled on exactly the worker service. This operational change does not require an application rewrite.

Railway's current trial avoids an immediate charge. Keep resource limits at the free/trial defaults and set a usage limit before launch.

## Backend — Heroku (later)

- Create an app using the Container stack and this repository's `heroku.yml`.
- Attach Heroku Postgres.
- Configure `SECRET_KEY_BASE`, `FRONTEND_URL`, `FRONTEND_HOST`, `ALLOWED_ORIGINS`, `API_HOST`, `ADMIN_EMAIL`, and a strong `ADMIN_PASSWORD`.
- Configure the S3-compatible variables from `.env.example` before enabling uploads.
- Keep `SEED_DEMO_DATA=false` in production.

The release command runs `bin/rails db:migrate`; the web process starts Puma. Verify `/api/health`, `/api/readiness`, registration/login, a complete candidate application, employer review and admin moderation after deployment.

The application remains portable: both providers run the same Docker image and PostgreSQL schema. Moving later requires a PostgreSQL dump/restore, copying object-storage data, and copying environment variables; no backend rewrite is required.

## Cost warning

Vercel Hobby can be used for private development, but its terms restrict commercial use. Heroku has no permanent free tier. Keep the services unlaunched while developing locally if the immediate budget must remain zero, or use temporary free-tier infrastructure and move to Heroku before commercial launch.
