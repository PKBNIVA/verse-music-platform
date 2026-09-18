# Product Requirements

## Candidate requirements
- Register and sign in securely.
- Build a music-native professional profile.
- Add credits, skills, genres, instruments, languages, availability and portfolio proof.
- Search across jobs, gigs, auditions, sessions, tours, internships and collaborations.
- Filter by function, location, workplace, paid status and verified employer.
- Save opportunities and create search alerts.
- Understand compensation, dates and portfolio requirements before applying.
- Apply once per opportunity and withdraw while the process is not finalized.
- Track pipeline status through offer/hire.
- Message an employer in the context of an opportunity.
- Receive notifications when application status changes.
- Report suspicious opportunities.
- Request professional verification.
- Review only employers with whom the candidate has a real application history.

## Employer requirements
- Create an organization-facing profile.
- Request organization verification.
- Create structured music-industry opportunities.
- Save drafts, submit for moderation and close listings.
- See moderation feedback.
- Review only applications to owned opportunities.
- Move applications through a controlled status pipeline.
- Search candidate profiles and inspect portfolio proof.
- Save/unsave talent to a shortlist.
- Message candidates.
- Receive notifications for new applications.

## Admin/operations requirements
- View marketplace health metrics.
- Moderate pending opportunities.
- See automated moderation hints without treating them as final decisions.
- Approve/reject verification requests.
- Review and resolve safety reports.
- Suspend/restore user accounts.
- Moderate employer reviews.
- Inspect audit history.

## Non-functional requirements
- Server-side authorization on every protected action.
- No plaintext passwords or raw session tokens in storage.
- Idempotent/additive database migrations.
- Duplicate application prevention.
- Ownership isolation for employer data.
- Reasonable payload size limits.
- Rate limiting.
- Persistent database storage.
- Mobile responsive primary workflows.
- Honest product claims: do not advertise features not implemented.
- Accessible labels/focus states and reduced motion preference should be supported before public launch.
- Production backups and recovery procedure before accepting business-critical data.


## 2026 SaaS + booking architecture expansion
Verse now treats four related but distinct workflows as first-class:
1. **Career hiring** — permanent, contract, tour, session, internship and collaboration opportunities.
2. **Band building** — define missing seats/roles in a project and publish those seats into the moderated hiring funnel.
3. **Act booking** — soloists, duos, trios, bands, ensembles, DJs, choirs and other acts receive date/location/event enquiries, issue quotes, accept bookings and collect deposits.
4. **SaaS operations** — subscriptions, trials, plan entitlements, workspace seats and commercial admin reporting.

Subscription revenue and performer-booking money are intentionally separate ledgers. Browser redirects never grant paid access; the server owns entitlements and signed gateway events own live subscription state. Marketplace settlement to performers is a later compliance-dependent layer, not simulated as a simple wallet transfer.
