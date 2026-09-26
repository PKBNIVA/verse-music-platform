# Verse Rails API

Ruby on Rails API for the Verse marketplace. PostgreSQL is the system of record and Active Storage provides direct uploads to any S3-compatible object store.

## Local setup

```bash
bundle install
bin/rails db:prepare
bin/rails server -p 3000
```

Run the Vite frontend with `VITE_API_URL=http://localhost:3000/api`.

## Production

For the initial deployment, Railway reads `railway.toml`, builds `backend/Dockerfile`, and supplies PostgreSQL through `DATABASE_URL`. The build context is the repository root; ignore rules live in `Dockerfile.dockerignore`. Gems are installed in frozen deployment mode from the committed `Gemfile.lock`.

Production requires external S3-compatible storage. Local disk storage is intentionally rejected by the readiness check because Heroku's filesystem is ephemeral.
