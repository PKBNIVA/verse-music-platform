# Architecture

## Current implementation

```text
React + Vite SPA
      |
      | same-site HTTPS / JSON API
      v
Node.js HTTP application
  ├─ security.mjs      session cookies, scrypt, rate limiting, headers
  ├─ app.mjs           routes, authorization, domain rules
  └─ db.mjs            schema, additive migrations, seed data
      |
      v
SQLite (WAL mode)
```

This architecture is intentionally dependency-light and fully runnable for a beta/small production deployment on a single Node instance with a persistent volume.

## Security boundary
- Server is authoritative for identity, roles, ownership and statuses.
- Session token lives in an **HttpOnly, SameSite=Lax cookie**, not browser localStorage.
- Passwords use Node `scrypt` with per-user salts.
- Session tokens are random and only their SHA-256 hashes are persisted.
- Suspended accounts cannot use authenticated endpoints.
- Employer candidate/application access is scoped to the authenticated employer.
- Admin-only moderation routes enforce server-side roles.
- State-changing marketplace events are audit logged where materially important.
- Rate limits are applied to authentication and overall API traffic.
- Production CORS is allowlist-based.
- Basic browser security headers are set by the server.

## Data domains
- Identity: users, profiles, sessions
- Opportunities: jobs (extended into opportunity taxonomy), saved_jobs, job_alerts
- Hiring: applications, application_events, talent_shortlists
- Proof: portfolio_items
- Communication: conversations, messages, notifications
- Trust: verification_requests, reports, reviews, audit_logs
- Education: career_resources

## Production-scale target
For materially larger traffic or multi-instance deployment:
1. PostgreSQL as the transactional system of record.
2. Redis for distributed rate limits, ephemeral presence and queues.
3. Object storage + CDN for resume/audio/video/image uploads.
4. Background worker for email, alerts, moderation checks and media processing.
5. Search engine (Postgres FTS first; OpenSearch only when justified).
6. Transactional email/SMS provider for verification, recovery and alerts.
7. Observability: structured logs, error tracking, metrics, traces.
8. Secrets manager and managed database backups/PITR.
9. WAF/CDN in front of public endpoints.
10. Separate admin/support permissions instead of a single super-admin role.

## Important architectural next step
The first major refactor after product validation should introduce **organizations + organization_members** so a label/studio can have owners, recruiters, hiring managers and read-only collaborators without sharing one employer credential.


## 2026 SaaS + booking architecture expansion
Verse now treats four related but distinct workflows as first-class:
1. **Career hiring** — permanent, contract, tour, session, internship and collaboration opportunities.
2. **Band building** — define missing seats/roles in a project and publish those seats into the moderated hiring funnel.
3. **Act booking** — soloists, duos, trios, bands, ensembles, DJs, choirs and other acts receive date/location/event enquiries, issue quotes, accept bookings and collect deposits.
4. **SaaS operations** — subscriptions, trials, plan entitlements, workspace seats and commercial admin reporting.

Subscription revenue and performer-booking money are intentionally separate ledgers. Browser redirects never grant paid access; the server owns entitlements and signed gateway events own live subscription state. Marketplace settlement to performers is a later compliance-dependent layer, not simulated as a simple wallet transfer.
