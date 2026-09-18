# Verse deployment: Vercel + Heroku

## Frontend — Vercel

- Import this GitHub repository.
- Framework preset: Vite.
- Build command: `npm run build`.
- Output directory: `dist`.
- Add `VITE_API_URL=https://<heroku-app>.herokuapp.com/api`.

`vercel.json` includes SPA routing and security/cache headers.

## Backend — Heroku

- Create an app using the Container stack and this repository's `heroku.yml`.
- Attach Heroku Postgres.
- Configure `SECRET_KEY_BASE`, `FRONTEND_URL`, `FRONTEND_HOST`, `ALLOWED_ORIGINS`, `API_HOST`, `ADMIN_EMAIL`, and a strong `ADMIN_PASSWORD`.
- Configure the S3-compatible variables from `.env.example` before enabling uploads.
- Keep `SEED_DEMO_DATA=false` in production.

The release command runs `bin/rails db:migrate`; the web process starts Puma. Verify `/api/health`, `/api/readiness`, registration/login, a complete candidate application, employer review and admin moderation after deployment.

## Cost warning

Vercel Hobby can be used for private development, but its terms restrict commercial use. Heroku has no permanent free tier. Keep the services unlaunched while developing locally if the immediate budget must remain zero, or use temporary free-tier infrastructure and move to Heroku before commercial launch.
