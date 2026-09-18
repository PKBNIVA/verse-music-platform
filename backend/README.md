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

The repository root contains `heroku.yml`; create a Heroku app using the container stack, attach Heroku Postgres, configure the variables in `.env.example`, and deploy the repository. The release phase runs migrations before the web process is replaced.

Production requires external S3-compatible storage. Local disk storage is intentionally rejected by the readiness check because Heroku's filesystem is ephemeral.
