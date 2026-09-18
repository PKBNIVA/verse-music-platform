# Verse Launch Hardening — v0.3.0

This revision implements the highest-impact gaps identified in the product/SEO/operations audit without pretending that external infrastructure or regulatory work is already complete.

## Implemented in this revision

### Public discovery & SEO
- Removed `noindex,nofollow` from the app shell.
- Public music opportunities at `/music-jobs` and `/opportunities/:id`.
- Public professional directory at `/music-professionals` and `/professionals/:id`.
- Public live-act directory at `/book-music` and `/acts/:id`.
- Dynamic `robots.txt`.
- Dynamic XML sitemap containing published opportunities, public professionals and active acts.
- Server-side injection of page title, description, canonical URL, OpenGraph metadata and JSON-LD into the built HTML shell.
- `JobPosting` JSON-LD for public opportunity pages.
- `ProfilePage`/`Person` JSON-LD for public professional pages.
- `PerformingGroup` JSON-LD for act pages.
- Private/admin application paths excluded from crawling through robots rules.

### Professional identity & recruiter search
Profiles now support structured music-industry signals:
- Professional roles
- Instruments
- Genres
- Skills
- Gear / consoles / rigs
- DAWs / software
- Years of experience
- Remote-recording readiness
- Sight-reading
- National/international travel readiness
- Passport/touring readiness
- Hourly, session, show, tour-day and day rates
- Credits, languages, availability and open-to preferences

Recruiter search can filter/query against roles, instruments, genres, location, software, remote-recording readiness, sight-reading, national travel, recent activity and rate ceiling.

### Recruiter workflow
- Screening questions on opportunities (up to 8).
- Screening answers stored with applications.
- Internal recruiter rating (1–5).
- Internal recruiter notes.
- Talent folders for reusable candidate groups/projects.
- Existing shortlist remains available as a quick one-click list.

### Availability & urgent replacement
- Availability windows with `available`, `hold`, `tentative`, `booked`, `unavailable` statuses.
- City-specific availability records.
- Urgent replacement requests with role, instrument, city, exact time, budget and travel context.
- Professionals can respond with availability note and rate.
- Request owners can inspect responses and close/fill requests.
- Navigation entry points for Availability and Urgent Replacement.

### Account recovery & trust
- Email verification token lifecycle.
- Password reset token lifecycle.
- Expiring one-time tokens stored hashed in the database.
- Existing sessions invalidated after password reset.
- Optional transactional-email webhook adapter.
- Development-only debug verification/reset links when no production mailer is configured.
- Forgot-password UI.
- Verify-email and reset-password UI.

### Operational readiness
- `/api/readiness` reports critical production configuration status.
- Checks cover public base URL, secure cookies, allowed origins, transactional email, Razorpay configuration and non-default admin password.
- Fixed example API port to match the actual server/Vite proxy (`4173`).
- Expanded report entity support to acts, bookings and urgent requests.
- Public profile responses no longer expose private email, phone or precise last-login timestamp.

## Intentionally not faked

These still require real external infrastructure, credentials, legal/compliance work or a larger migration and therefore are **not** presented as completed:

1. Managed PostgreSQL migration for multi-instance production scale.
2. S3/R2/GCS object storage, signed uploads, media transcoding and malware scanning.
3. A real transactional email provider connection (Brevo/SES/Postmark/SendGrid etc.). The adapter is implemented; provider credentials/templates are not.
4. Real Razorpay Test/Live credentials, production Plan IDs and webhook configuration.
5. Razorpay Route/linked-account payouts, performer KYC and marketplace settlement compliance.
6. Automated GST/TDS invoicing and statutory reporting.
7. Jurisdiction-specific legal review of Terms, Privacy, cancellations, refunds and marketplace policies.
8. Managed logging/APM/error tracking (Sentry/Datadog/etc.).
9. Automated backups/PITR supplied by the production database provider.
10. Production CDN/WAF/DDoS controls supplied by deployment infrastructure.
11. Google Search Console/Bing Webmaster verification, domain ownership and sitemap submission.
12. Real marketplace supply/demand acquisition and moderation staffing.

## QA

Automated suites:

```bash
npm run test:all
```

Covers:
- Core hiring flow
- Band booking/SaaS/payment flow
- Launch-hardening flow
- Public SEO sitemap/robots output
- Dynamic JobPosting metadata injection
- Email verification
- Availability
- Urgent replacement
- Screening questions/answers
- Recruiter notes/rating
- Talent folders

All three backend suites pass on a fresh temporary database.

The environment used to prepare this revision repeatedly timed out during `npm install`, so the dependency-installed Vite production build could not be executed here. All 98 TypeScript/TSX source files were syntax-parsed successfully using the installed TypeScript compiler.
