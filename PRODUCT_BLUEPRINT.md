# Verse — Product Blueprint

## Product thesis
Verse should not be positioned as another generic job board with a music skin. The defensible product is a **professional operating network for music careers**: identity and credits, opportunity discovery, trust, hiring workflow, communication, reputation, and eventually contracts/payments/rights-aware collaboration.

## Core user groups
1. **Music professionals** — artists, singers, instrumentalists, producers, composers, songwriters, engineers, DJs, live crew, managers, marketers, A&R, publishing/rights, label operations, music-tech.
2. **Organizations** — labels, studios, publishers, management companies, agencies, venues, festivals, production houses, artist-service firms, music-tech companies, brands and event companies.
3. **Platform operations** — trust & safety, verification, moderation, marketplace quality, customer support and growth.

## Core marketplace loop
**Identity → proof → discovery → trust check → application/conversation → evaluation → shortlist/interview/offer/hire → verified outcome/review → stronger reputation**

## Opportunity taxonomy
The product now distinguishes:
- Job
- Gig
- Audition
- Session
- Tour
- Internship
- Collaboration

Each opportunity can also carry function, workplace mode, pay range/period, genre/repertoire, skills, languages, start date, deadline, duration, open slots and portfolio requirement.

## Product principles
- **Proof over claims:** credits and work samples should matter more than decorative profile completion.
- **Clear money:** compensation should be strongly encouraged and eventually required for most opportunity types.
- **No pay-to-apply:** candidate access to legitimate work should remain free.
- **Trust is workflow, not a badge:** verification, moderation, reporting, audit and review eligibility work together.
- **Transparent matching:** current profile-fit scores are rules-based and explainable; do not label them AI.
- **Music-native data:** genres, instruments, languages, DAWs, live/studio context, credits and work format are first-class fields.
- **Mobile-first operations:** many music-industry users act from phones while travelling, rehearsing or working shows.
- **Do not automate spam:** avoid “AI auto-apply” or mass candidate outreach that destroys marketplace signal.

## Current functional scope
- Candidate/employer/admin authentication with HttpOnly sessions
- Role authorization and suspended-account enforcement
- Candidate and employer profiles
- Credits, skills, genres, instruments, languages, availability and rates
- Portfolio links
- Seven opportunity types with richer structured fields
- Admin moderation before publication
- Search/filtering, saved opportunities and alerts
- Applications with duplicate prevention and portfolio requirement checks
- Employer applicant workflow through offer/hire
- Talent search and shortlists
- In-platform messaging and unread state
- Notifications
- Professional/organization verification requests
- Safety reports
- Moderated employer reviews restricted to real applicant history
- Admin trust & operations dashboard
- Audit logging
- Rate limits, security headers and stricter CORS
- Backend smoke test

## North-star metrics
Do not optimize for raw registrations or applications. Prioritize:
- % of live opportunities receiving at least 3 qualified applicants
- Median time to first qualified applicant
- Application → shortlist conversion
- Shortlist → interview conversion
- Interview → hire conversion
- % opportunities with disclosed compensation
- % active employers verified
- % active professionals with portfolio proof / credits
- Repeat employer posting rate
- Repeat professional engagement after 30/90 days
- Report rate per 1,000 opportunities and resolution time
- Successful conversations per opportunity

## Monetization direction
Launch with free core access to build liquidity and trust. Later monetize employer/team value rather than candidate desperation:
- team seats and organization workspaces
- higher active-opportunity limits
- advanced sourcing/search
- integrations and exports
- promoted opportunities with strict labeling
- booking/contract/escrow transaction fees
- recruiter workflow/API products
- enterprise verification/compliance

Candidate application fees should not be part of the model.


## 2026 SaaS + booking architecture expansion
Verse now treats four related but distinct workflows as first-class:
1. **Career hiring** — permanent, contract, tour, session, internship and collaboration opportunities.
2. **Band building** — define missing seats/roles in a project and publish those seats into the moderated hiring funnel.
3. **Act booking** — soloists, duos, trios, bands, ensembles, DJs, choirs and other acts receive date/location/event enquiries, issue quotes, accept bookings and collect deposits.
4. **SaaS operations** — subscriptions, trials, plan entitlements, workspace seats and commercial admin reporting.

Subscription revenue and performer-booking money are intentionally separate ledgers. Browser redirects never grant paid access; the server owns entitlements and signed gateway events own live subscription state. Marketplace settlement to performers is a later compliance-dependent layer, not simulated as a simple wallet transfer.
