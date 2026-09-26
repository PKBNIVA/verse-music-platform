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
`main` or `render.yaml`. The legacy Node/SQLite server (`server/`) and `heroku.yml` have been
removed from `production`; the Rails API in `backend/` is the only backend.

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
npm run test:all            # frontend source smoke tests (tests/frontend-*.mjs)
npm audit --omit=dev --audit-level=high
npm run qa:e2e
cd backend && bin/rails test && bin/rails zeitwerk:check
bundle exec brakeman --no-pager --exit-on-warn   # reviewed exceptions: config/brakeman.ignore
bundle exec bundler-audit check --update
```

`backend/Gemfile.lock` and `backend/db/schema.rb` are committed. After adding a migration, run
`bin/rails db:migrate` and commit the regenerated `db/schema.rb`; CI fails if it is stale.
After changing the Gemfile, run `bundle lock` and commit the lockfile; the Docker image installs
in frozen/deployment mode and fails if the two disagree.

See [DEPLOYMENT.md](DEPLOYMENT.md) for release configuration, required environment
variables, health checks, rollback, backups, and synthetic QA procedures.
