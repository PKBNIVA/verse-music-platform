# Rails 8 upgrade (7.2.3.2 → 8.1.4)

Rails 7.2 security support ended 2026-08-09 (AUDIT.md). The backend now runs Rails 8.1.4
with `config.load_defaults 8.1`. No database migration is part of this change.

## What changed

| Area | Change |
| --- | --- |
| Gems | `rails` 7.2.3.2 → 8.1.4 (all frameworks). `action_text-trix` 2.1.19 added (split out of actiontext); `cgi` and `benchmark` dropped as transitive deps. No other gem moved (`bundle update rails --conservative`). Lockfile platforms and Bundler 4.0.9 unchanged. |
| Deprecations | Implicit `ActiveRecord::Base.connection` checkout (soft-deprecated in 7.2) replaced with `lease_connection` (same per-thread semantics) in the tester/reviews controllers, `ReadinessChecks`, `SyntheticQa::Demo` and two test helpers. The test env now sets `active_support.deprecation = :raise` and `permanent_connection_checkout = :deprecated`, so new deprecations fail CI. |
| Defaults | `load_defaults 7.2` → `8.1`. All 8.0 and 8.1 defaults were first enabled one by one in `new_framework_defaults_8_{0,1}.rb`, the suite stayed green, then the files were removed. |
| Production config | `silence_healthcheck_path = "/api/live"` (Railway deploy probes no longer fill the log); `active_record.attributes_for_inspect = [:id]` (record `#inspect` in errors/console shows no PII). |
| Log filtering | Added the Rails 8 generator entries `passw _key crypt salt certificate ssn cvv cvc` to `filter_parameters` (logs and `#inspect` only). |
| Schema | `db/schema.rb` header is `ActiveRecord::Schema[8.1]`; `plpgsql` is written as `pg_catalog.plpgsql`. Nothing else. |
| CI | Rails 8 `db:migrate` on an **empty** database loads `db/schema.rb` instead of running migrations. The drift check now runs `rm db/schema.rb && bin/rails db:migrate` so every migration still runs. |
| Brakeman | The Rails 7.2 EOL ignore entry is gone; `brakeman.ignore` is empty and Brakeman reports 0 warnings. |

### Defaults now in effect (all from `load_defaults 8.1`)

- `action_dispatch.strict_freshness = true`: only If-None-Match counts when both conditional headers are sent. The API uses no conditional GETs.
- `Regexp.timeout = 1`: global ReDoS guard. A regex that runs longer than 1s raises `Regexp::TimeoutError`.
- `to_time` keeps the receiver's zone (always on in 8.1). The app works in UTC.
- `action_controller.escape_json_responses = false` and `active_support.escape_js_separators_in_json = false`: `<`, `>`, `&`, U+2028 and U+2029 are no longer `\u`-escaped in JSON. The SPA parses JSON, so it gets the same values. API JSON is never embedded in HTML.
- `active_record.raise_on_missing_required_finder_order_columns = true`: `first`/`last` without an `order` raise on the key-less join models (OrganizationMember, SavedJob, TalentFolderMember, TalentShortlist, UrgentRequestResponse). No code calls them that way.
- `action_controller.action_on_path_relative_redirect = :raise`: the API never redirects.
- `action_view.render_tracker = :ruby`, `remove_hidden_field_autocomplete = true`: no views or forms, so no effect.
- `yjit = !Rails.env.local?`: YJIT stays on in production (as under 7.2) and is off in dev and test.

**Deferred defaults: none.**

## Developer-facing notes

- `bin/rails db:migrate` on a brand-new database now loads `schema.rb` and then dumps it again. PostgreSQL re-renders the `IN (...)` check constraints and the partial index as `ARRAY[('x'::character varying)::text, ...]`, so the dump shows a cosmetic diff. Don't commit that diff. To regenerate `schema.rb` for real, drop the database, delete `db/schema.rb`, then run `db:create db:migrate`, the same way CI does.
- `db:prepare` on an existing database (the Dockerfile `CMD`) works exactly as before: it only runs pending migrations.

## Rollback

There are no schema changes. `schema_migrations` is untouched and the last migration is still `20260926160000`. To roll back, redeploy the previous commit (`2bed034`) on Railway. The old code runs against the same database unchanged. No data or cache needs clearing: the cache format is unchanged and sessions are token rows in the database.

## What to watch after deploy

1. Deploy health: `/api/live` answers 200 within the healthcheck window, and `/api/readiness` answers 200.
2. `Regexp::TimeoutError` in errors or logs. This means a regex ran for more than 1s. Fix the pattern; don't raise the timeout.
3. `ActiveRecord::MissingRequiredOrderError` from a key-less model in a code path the tests don't cover.
4. `ActionController::Redirecting::UnsafeRedirectError`. None is expected.
5. GoodJob: the cron jobs (job alerts, auth cleanup, billing reconciliation, upload sweep) keep finishing. Check with `GoodJob::Job.where(finished_at: 1.hour.ago..)` in a console, or with the admin health view.
6. Frontend: payment, messaging and notification text containing `<`, `>` or `&` still renders correctly. The characters now arrive unescaped in the JSON; the parsed values are the same.

## Pre-existing items noticed (not changed here)

- `GoodJob.migrated?` returns `false` on a database built from the current migrations, on 7.2 as well as on 8.1. good_job 4.19.3 ships newer schema migrations (`rails g good_job:update`). Handle this separately.
- `RAILS_LOG_TO_STDOUT=true` in the Dockerfile is ignored by Rails 7.1+, which only honours an explicit `config.logger`. Production therefore logs to `log/production.log` inside the container, not to stdout. Consider `config.logger = ActiveSupport::TaggedLogging.logger($stdout)` in `production.rb`.
