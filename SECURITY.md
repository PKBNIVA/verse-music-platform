# Security Notes

## Implemented
- scrypt password hashing with unique salts
- HttpOnly SameSite session cookie
- hashed session tokens in database
- 7-day session expiry
- role and account-status authorization
- employer ownership checks
- candidate conversation membership checks
- duplicate application constraint
- payload limits
- API and authentication rate limits
- security headers
- production CORS allowlist
- audit logging for sensitive marketplace actions
- server-side validation for opportunity/application/review/report workflows

## Required before public production
- TLS everywhere
- email verification
- password reset with short-lived one-time token
- CSRF token if deployment architecture becomes cross-site or cookies become SameSite=None
- distributed rate limiting when multiple application instances are used
- WAF/bot management for abusive traffic
- malware scanning for uploaded files
- signed object-storage URLs and strict media MIME/size validation
- secrets manager
- database encryption/backups/PITR
- error monitoring with PII redaction
- dependency vulnerability scanning in CI
- SAST/secret scanning
- account deletion/export workflow
- admin MFA and narrower admin roles
- session/device management and forced logout controls
- abuse heuristics for mass messaging, scraping and fake listings


## 2026 SaaS + booking architecture expansion
Verse now treats four related but distinct workflows as first-class:
1. **Career hiring** — permanent, contract, tour, session, internship and collaboration opportunities.
2. **Band building** — define missing seats/roles in a project and publish those seats into the moderated hiring funnel.
3. **Act booking** — soloists, duos, trios, bands, ensembles, DJs, choirs and other acts receive date/location/event enquiries, issue quotes, accept bookings and collect deposits.
4. **SaaS operations** — subscriptions, trials, plan entitlements, workspace seats and commercial admin reporting.

Subscription revenue and performer-booking money are intentionally separate ledgers. Browser redirects never grant paid access; the server owns entitlements and signed gateway events own live subscription state. Marketplace settlement to performers is a later compliance-dependent layer, not simulated as a simple wallet transfer.
