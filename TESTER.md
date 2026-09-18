# Verse Tester & Release Gate — v0.5.0

Verse now has two complementary tester layers.

## 1. Live admin tester

Sign in as an admin and open `/admin/tester` (or use the **Live Tester** button in Trust & Operations).

The live tester is non-destructive. It checks:
- SQLite foreign-key integrity
- critical database tables
- duplicate account emails
- orphan portfolio records
- writable runtime data directory
- production URL / HTTPS readiness
- secure-cookie readiness
- search provider configuration
- email delivery configuration
- object-storage configuration

It is intended to be safe to run repeatedly on staging or production. It does not create jobs, bookings, charges, users or messages.

## 2. Automated full regression

Run:

```bash
npm run test:all
```

This executes the original hiring test, platform/SaaS/payment test, launch-hardening test, product-experience test, and the v0.5 full regression test.

The v0.5 regression additionally checks:
- Node source syntax
- every TS/TSX source file via TypeScript transpile diagnostics
- real local media upload with valid WAV data
- ffprobe media metadata extraction when available
- waveform generation when ffmpeg is available
- uploaded `/uploads/...` URLs can actually be saved as portfolio samples
- tagged portfolio persistence
- layman synonym search (`sound guy` -> FOH/live-sound concepts)
- talent-search synonym behavior
- recent profile activity
- 2-person candidate comparison with portfolio/availability
- Build My Crew recommendation rules
- Build My Crew -> Band Builder conversion
- robots.txt and sitemap essentials
- protected/search page `noindex`
- the live admin tester endpoint
- source regression scan for dummy OTP/mock auth/old token patterns
- accidental duplicate request-parser declaration

## Release gate

Do not ship a release when:
- `npm run test:all` fails
- `/admin/tester` has a failed critical/high-severity check
- production is using SQLite for multi-instance scale
- production email, object storage or Razorpay are expected but not configured
- Search Console / sitemap / canonical domain are not configured for the real domain

## What automation cannot prove

No automated tester can honestly prove “nothing can ever be missed.” Before a high-traffic commercial launch, also perform:
- real-browser testing on Chrome/Safari/Firefox/Edge
- Android + iPhone responsive testing
- accessibility testing with keyboard and screen reader
- load/concurrency testing on the production database/search cluster
- real Razorpay Test Mode subscription, cancellation, webhook and booking-payment tests
- object-storage malware/content validation tests
- transactional-email deliverability tests
- backup restore drill
- legal/privacy/cancellation policy review
- security penetration test
