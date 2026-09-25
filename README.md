# Verse music platform

Verse is a two-sided music careers, hiring, collaboration, and live-booking platform.

## Canonical production topology

| Layer | Provider | Source |
| --- | --- | --- |
| Web frontend | Vercel | repository root, Vite build |
| API and background jobs | Railway | `backend/Dockerfile` |
| Database | Railway PostgreSQL | `DATABASE_URL` |
| Canonical release branch | GitHub `production` | deploy only after CI passes |

Production URLs:

- Web: https://verse-music-platform.vercel.app
- API: https://verse-music-platform-production.up.railway.app/api
- Liveness: https://verse-music-platform-production.up.railway.app/api/live
- Health: https://verse-music-platform-production.up.railway.app/api/health
- Readiness: https://verse-music-platform-production.up.railway.app/api/readiness

The legacy Node/Render line on `main` is not the production application. Do not deploy
`main`, `render.yaml`, or the legacy Node server.

## Local development

```bash
npm ci
npm run dev
```

Run the Rails API separately:

```bash
cd backend
bundle install
bin/rails db:prepare
bin/rails server
```

## Verification

```bash
npm run build
npm run test:all
npm run qa:e2e
cd backend && bin/rails test && bin/rails zeitwerk:check
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for release configuration, required environment
variables, health checks, rollback, backups, and synthetic QA procedures.
