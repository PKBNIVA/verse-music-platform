# Product Roadmap

## Phase 0 — Foundation (implemented in this package)
Trustworthy full-stack core: secure auth, profiles, proof, opportunity taxonomy, moderation, applications, messaging, alerts/saves, notifications, verification, reports, reviews, admin operations and audit logs.

## Phase 1 — Launch quality
Highest priority before a broad public launch:
- Email verification and forgot/reset password flows
- Organization/team accounts and invitations
- Real file/media uploads to object storage
- Resume/CV and structured credit import
- Application screening questions
- Interview scheduling and calendar integration
- Email/push notification delivery for alerts and status updates
- Employer job editing/version history
- Admin support notes, moderation macros and appeal workflow
- Terms/privacy/consent surfaces and data-deletion/export workflow
- Accessibility audit and mobile navigation redesign
- Automated database backups and error monitoring
- Anti-spam and account-abuse controls

## Phase 2 — Music network moat
- Verified credit graph linking people ↔ releases ↔ roles ↔ organizations
- Collaboration/project rooms
- Availability calendar for session/touring professionals
- Roster management for agencies/managers
- Venue/studio/crew discovery
- Referral and trusted-introduction graph
- Saved talent lists by project
- Audition submission workflow with media review
- Offer/engagement letter templates
- Rate cards and budget-range guidance based on consented marketplace data
- Music-business learning paths by function

## Phase 3 — Transactions
Only after trust and dispute operations are ready:
- Booking requests and statements of work
- Milestones/deliverables
- Escrow or protected payments via regulated payment partner
- Cancellation terms
- Invoices and payout tracking
- Dispute handling
- Platform transaction fees

## Phase 4 — Intelligence
AI should assist users without inventing authority:
- Structured job-description quality assistant
- Credit/portfolio metadata extraction with user confirmation
- Search query expansion
- Explainable candidate/opportunity recommendations
- Duplicate/scam pattern detection for moderators
- Message drafting and scheduling assistance
- Career path suggestions based on explicit evidence

Do **not** ship autonomous mass auto-apply or opaque candidate rejection scores.

## Phase 5 — Scale / ecosystem
- PostgreSQL + queues + distributed infrastructure
- Organization RBAC and enterprise SSO
- ATS/HRIS integrations
- Public API/webhooks
- Partner job ingestion with provenance and deduplication
- Cross-border currency/tax/compliance support
- Multi-language product localization
- Advanced marketplace analytics


## 2026 SaaS + booking architecture expansion
Verse now treats four related but distinct workflows as first-class:
1. **Career hiring** — permanent, contract, tour, session, internship and collaboration opportunities.
2. **Band building** — define missing seats/roles in a project and publish those seats into the moderated hiring funnel.
3. **Act booking** — soloists, duos, trios, bands, ensembles, DJs, choirs and other acts receive date/location/event enquiries, issue quotes, accept bookings and collect deposits.
4. **SaaS operations** — subscriptions, trials, plan entitlements, workspace seats and commercial admin reporting.

Subscription revenue and performer-booking money are intentionally separate ledgers. Browser redirects never grant paid access; the server owns entitlements and signed gateway events own live subscription state. Marketplace settlement to performers is a later compliance-dependent layer, not simulated as a simple wallet transfer.
