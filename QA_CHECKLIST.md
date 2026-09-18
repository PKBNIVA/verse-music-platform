# QA Checklist

## Automated checks included
- `node tests/backend-smoke.mjs` exercises registration, employer job creation, admin approval, save, apply, employer shortlist, candidate notification, report creation and admin stats.
- Node syntax checks pass for server modules.
- TypeScript/TSX source files were parsed with TypeScript transpilation without syntax errors during packaging.

## Manual browser checks before release
- candidate registration/login/logout/reload session
- employer registration/login/logout/reload session
- admin login and unauthorized route blocking
- mobile nav at 320/375/430 widths
- keyboard-only navigation
- screen-reader labels for forms and icon buttons
- dark-mode contrast
- long company/job/candidate names
- empty states
- API error states and offline handling
- duplicate apply
- portfolio-required apply
- expired application deadline
- suspended user session
- employer cannot access another employer’s applications
- candidate cannot access admin/employer pages
- messaging deep-link via `?conversation=`
- unread notification count/read state
- verification duplicate request
- report moderation
- review eligibility enforcement
- job rejection note visibility
- search combinations and no-result state
- save/unsave race conditions
- date/time timezone display


## 2026 SaaS + booking architecture expansion
Verse now treats four related but distinct workflows as first-class:
1. **Career hiring** — permanent, contract, tour, session, internship and collaboration opportunities.
2. **Band building** — define missing seats/roles in a project and publish those seats into the moderated hiring funnel.
3. **Act booking** — soloists, duos, trios, bands, ensembles, DJs, choirs and other acts receive date/location/event enquiries, issue quotes, accept bookings and collect deposits.
4. **SaaS operations** — subscriptions, trials, plan entitlements, workspace seats and commercial admin reporting.

Subscription revenue and performer-booking money are intentionally separate ledgers. Browser redirects never grant paid access; the server owns entitlements and signed gateway events own live subscription state. Marketplace settlement to performers is a later compliance-dependent layer, not simulated as a simple wallet transfer.

## v0.3.0 automated launch-hardening checks
- [x] Rich professional profile persistence
- [x] Email verification token flow
- [x] Public talent search
- [x] Availability window create/list
- [x] Urgent replacement create/respond/review
- [x] Screening question persistence
- [x] Screening answer persistence
- [x] Recruiter rating/note persistence
- [x] Talent folder create/add/read
- [x] Dynamic robots.txt
- [x] Dynamic sitemap.xml includes published job
- [x] Dynamic JobPosting JSON-LD injection
- [x] 98 TS/TSX files syntax-parse cleanly
- [x] backend-smoke PASS
- [x] platform-smoke PASS
- [x] launch-hardening-smoke PASS
