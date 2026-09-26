# Verse API contract

Rails 7.2 API in `backend/`, served under `/api`. The contract below is enforced by
`backend/test/integration/api_matrix_test.rb` (every route x every role),
`api_frontend_contract_test.rb` (keys the React pages read), `api_error_shape_test.rb`,
`api_security_probes_test.rb` and `api_query_budget_test.rb`. A route added without a matrix
spec fails the inventory test.

## Conventions

- **Auth**: `Authorization: Bearer <accessToken>` from `POST /auth/login` or `/auth/register`.
  Sessions last 30 days; logout revokes one. Suspended or pending accounts get `403 ACCOUNT_INACTIVE`.
- **Roles**: `jobseeker` (professional), `employer`, `admin`. In the tables, *talent* means
  jobseeker or employer (both may post opportunities, build acts and book), *any* means every
  signed-in role, *public* needs no token.
- **Casing**: request bodies are camelCase. Responses mix camelCase (computed fields) and
  snake_case (raw columns such as `opportunity_kind`, `created_at`); see P3 in AUDIT.md.
- **Ids** are prefixed strings (`job_…`, `user_…`, `acts_…`). Unknown ids are `404`.
- **Email verification**: when `REQUIRE_EMAIL_VERIFICATION=true`, non-admin users with an
  unverified email get `403 EMAIL_NOT_VERIFIED` on every non-GET request except `/auth/*`.

### Status codes and error body

Every error is JSON `{ "error": "<human message>", "code": "<MACHINE_CODE>" }` (`code` optional).

| Status | Meaning | Typical codes |
| --- | --- | --- |
| 400 | Invalid value for a whitelisted field, malformed JSON, missing parameter | `MALFORMED_JSON`, `PARAMETER_MISSING`, `BAD_REQUEST`, `INVALID_ROLE`, `TOKEN_INVALID`, `INVALID_VERIFICATION_KIND`, `INVALID_MEMBER_STATUS` |
| 401 | No or unknown token; wrong login | — |
| 402 | Plan capacity reached | `PLAN_LIMIT`, `PLAN_LIMIT_REACHED` |
| 403 | Signed in with the wrong role, not permitted, inactive account | `ACCOUNT_INACTIVE`, `EMAIL_NOT_VERIFIED`, `REVIEW_NOT_ELIGIBLE` |
| 404 | Unknown id **or another user's private resource** (never reveals existence) | — |
| 409 | State conflict (duplicate, invalid transition, already paid) | `CONFLICT`, `REVIEW_EXISTS` |
| 422 | Validation failure | `MISSING_FIELD`, `INVALID_VALUE`, `OUT_OF_RANGE`, `INVALID_REPORT`, `INVALID_VERIFICATION_REQUEST` |
| 429 | Rate limited (`Retry-After` on per-user limits) | `RATE_LIMITED` |
| 502/503 | Payment provider failure / not configured; readiness not ready | `NOT_READY` |

Generic mappings in `ApplicationController`: `RecordNotFound` 404, `RecordInvalid` 422,
`NotNullViolation` 422 `MISSING_FIELD` (names the camelCase field), `RecordNotUnique` 409
`CONFLICT`, `ActiveModel::RangeError` 422 `OUT_OF_RANGE`, enum `ArgumentError` and NUL bytes
422 `INVALID_VALUE`, `ParameterMissing` 400, `BadRequest` 400 (keeps its message),
malformed JSON 400 `MALFORMED_JSON`.

### Pagination and bounds

No endpoint accepts `limit`/`page`/`offset`; such parameters are ignored (negative or huge values
are harmless). Lists are capped server-side where noted; **unbounded** lists return every row
the caller owns and are tracked in `api_query_budget_test.rb` (`UNBOUNDED`).

### Rate limits (fixed windows, `Rails.cache`; per process unless `REDIS_URL` is set)

| Action | Limit |
| --- | --- |
| `POST /auth/register` | 20 / hour / IP |
| `POST /auth/login` failures | 10 / 15 min per email+IP, 100 per email, 50 per IP (successes are free) |
| `POST /auth/request-email-verification` | 5 / hour / IP |
| `POST /auth/forgot-password` | 10 / hour / IP |
| `POST /conversations` | 20 / hour / user |
| `POST /conversations/:id/messages` | 120 / hour / user |
| `POST /reports` | 30 / hour / user |

## Endpoints

### Health and catalog (public)

| Method | Path | Response | Notes |
| --- | --- | --- | --- |
| GET | `/health`, `/live` | `{ok, service, release, time}` | Liveness, always 200 |
| GET | `/readiness` | same; 503 adds `{error, code: NOT_READY}` | No diagnostics |
| GET | `/taxonomy` | `{opportunityKinds, functionAreas, workplaces, currencies, actTypes, eventTypes, engagementTypes, roleCategories, instruments}` | Static |
| GET | `/resources` | `{resources: [{id, title, category, description, url}]}` | **Unbounded** |
| GET | `/search?q=&type=jobs\|talent\|acts\|samples` | `{results: [{type, id, url, title, subtitle, description, tags}], interpretedAs, provider, status}` | ≤ 60 results; synonyms expand `q` |
| GET | `/search/status` | `{provider, healthy, fallback}` | |
| GET | `/billing/plans` | `{plans: [{code, name, monthly, trialDays, activePosts, seats, shortlist, bookings}]}` | |

### Auth and profile

| Method | Path | Auth | Params | Response / errors |
| --- | --- | --- | --- | --- |
| POST | `/auth/register` | public | `name, email, password (≥10), role: jobseeker\|employer` | 201 `{user, accessToken, verificationRequired, verificationDelivery}`; 422 `INVALID_ROLE`/validation; 409 duplicate |
| POST | `/auth/login` | public | `email, password` | `{user, accessToken}`; 401; 403 inactive; 429 |
| POST | `/auth/logout` | public | bearer token | `{ok}` |
| POST | `/auth/request-email-verification` | any | — | `{ok, alreadyVerified?, debugLink?}` |
| POST | `/auth/verify-email` | public | `token` | `{ok}`; 400 `TOKEN_INVALID` |
| POST | `/auth/forgot-password` | public | `email` | `{ok}` (always) |
| POST | `/auth/reset-password` | public | `token, password` | `{ok}`; 400 |
| GET | `/me` | any | — | `{user}`: user columns + camelCase profile fields, `profileComplete`, `emailVerified` |
| PUT | `/profile` | talent | whitelisted profile fields (`headline, bio, skills[] …, companyName …, hourlyRate …`) | `{user}`; 422 unsafe URL. `verified`, `role`, `status` are ignored |

### Opportunities and applications

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/jobs` | public | `q, location, kind, function, workplace, experience, paid=true, verified=true` | `{jobs: [job + saved]}`; ≤ 250 |
| GET | `/jobs/:id` | public | — | `{job: job + applied, saved}`; drafts/pending only to owner and admin (else 404) |
| POST | `/jobs` | talent | `title, location, description (≥60), type, status: draft\|(pending)…` | 201 `{id, status, moderationFlags}`; 402 `PLAN_LIMIT` unless draft |
| POST | `/jobs/:id/apply` | jobseeker | `coverLetter, screeningAnswers[]` | 201 `{id, status: Applied}`; 409 own/duplicate/deadline/portfolio |
| GET | `/saved-jobs` | jobseeker | — | `{jobs}` **unbounded** |
| POST / DELETE | `/saved-jobs/:id` | jobseeker | — | `{ok}` (idempotent) |
| GET | `/applications` | jobseeker | — | `{applications: [{id, status, title, company, location, opportunityKind, workplace, createdAt, interviewDate, …}]}` **unbounded** |
| DELETE | `/applications/:id` | jobseeker (own) | — | `{ok}`; 409 Hired/Rejected |
| GET | `/job-alerts` | jobseeker | — | `{alerts}` **unbounded** |
| POST | `/job-alerts` | jobseeker | `name, query, location, opportunityKind, functionArea, remoteOnly, frequency: daily\|weekly\|saved` | 201 `{id}`; 400 frequency |
| PATCH/PUT | `/job-alerts/:id` | jobseeker (own) | same | `{alert}` |
| DELETE | `/job-alerts/:id` | jobseeker (own) | — | `{ok}` |
| PATCH/PUT | `/employer/jobs/:id` | talent (own job) | `status: draft\|pending\|closed` | `{ok}`; 400 |
| GET | `/employer/applications` | talent | `jobId` | `{applications: [… candidateName, candidateEmail, allowedNextStatuses]}` **unbounded** |
| PATCH/PUT | `/employer/applications/:id` | talent (own job) | `status` (transition), `interviewDate`, `recruiterRating 1-5`, `recruiterNote`, `note` | `{ok, application}`; 400/409/422 |
| GET | `/dashboard` | any | — | jobseeker: `{applications, interviews, saved, profileScore, recommendedJobs[≤6 with fitScore]}`; others: `{jobs, published, activeJobs, applications, shortlisted, recentJobs[≤8]}` |

### Portfolio, uploads, notifications, safety

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/portfolio` | jobseeker | — | `{items}` **unbounded** |
| POST | `/portfolio` | jobseeker | `type, title, url, description, creditedAs, year, featured, thumbnailUrl, waveformUrl, visibility, tags[] …, mediaMetadata{}` | 201 `{id, item}` |
| PATCH/PUT/DELETE | `/portfolio/:id` | jobseeker (own) | as create (`type` currently required on update) | `{item}` / `{ok}` |
| POST | `/uploads/presign` | any | `filename, contentType (audio/mpeg, audio/wav, video/mp4, image/jpeg\|png\|webp, application/pdf), size ≤ 100 MB` | `{mode: direct, uploadUrl, method, headers, publicUrl}` or `{mode: proxied, uploadUrl}`; 422 |
| PUT | `/uploads/local` | any | raw body, `Content-Type`, `X-Filename` | 201 `{url}`; 422 type/size/content sniff; 403 when disabled |
| GET | `/notifications` | any | — | `{notifications: [{id, type, title, body, link, readAt, createdAt}], unread}`; ≤ 100 |
| GET | `/notifications/unread` | any | — | `{unread}` |
| PATCH/PUT | `/notifications/:id` | any (own) | `read: false` to unread | `{ok}` |
| POST | `/reports` | any | `entityType (≤40), entityId (≤120), reason (≤200), details (≤5000)` — strings | 201 `{id}`; 422 `INVALID_REPORT`; 429 |
| POST | `/verification-requests` | any | `kind: professional` (jobseeker) or `organization` (employer), `evidenceUrl (http[s], ≤2048), note (≤2000)` | 201 `{id}`; 400 `INVALID_VERIFICATION_KIND`; 422 |
| GET | `/reviews` | public | `employerId` | `{reviews, eligibleEmployers (jobseekers only)}` **unbounded** |
| POST | `/reviews` | jobseeker | `employerId, rating 1-5, title, body` | 201; 403 `REVIEW_NOT_ELIGIBLE` (needs a Hired application); 409 `REVIEW_EXISTS` |

### Talent discovery

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/public/talent` | public | `q, location, role, instrument, verified, remoteRecording` | `{talent}` ≤ 100; no email/phone/status |
| GET | `/public/talent/:id` | public | — | `{professional, portfolio (public items)}`; incomplete/suspended → 404 |
| GET | `/candidates` | talent | as above | `{candidates: [… shortlisted]}` ≤ 100 |
| GET | `/candidates/:id` | talent | — | `{candidate, portfolio}`; records a recent-activity row |
| GET | `/candidates/compare/list` | talent | `ids=a,b[,c,d]` (2-4) | `{professionals: [… portfolio ≤8, availability ≤5]}`; 400 fewer than 2 |
| POST / DELETE | `/shortlists/:id` | talent | `note` | `{ok}`; 402 plan limit |
| GET / DELETE | `/recent-activity` | talent | — | `{items}` ≤ 30 / `{ok}` |
| GET | `/employers` | any | — | `{employers: [{id, name, companyName, …, verified}]}` **unbounded** |
| GET | `/talent-folders` | talent | — | `{folders: [… count]}` **unbounded, N+1** |
| POST | `/talent-folders` | talent | `name, description` | 201 `{id}`; 422 `MISSING_FIELD` |
| GET / DELETE | `/talent-folders/:id` | talent (own) | — | `{folder, candidates}` (discoverable only) / `{ok}` |
| POST | `/talent-folders/:id/candidates/:candidateId` | talent (own) | `note` | 201 `{ok}`; hidden talent → 404 |
| GET | `/availability` | talent | — | `{windows: [{id, startAt, endAt, status, city, note}]}` **unbounded** |
| POST / DELETE | `/availability[/:id]` | talent (own) | `startAt, endAt, status, city, note` | 201 `{id}` / `{ok}`; 422 |

### Messaging

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/conversations` | any | — | `{conversations: [{id, candidateName, employerName, jobTitle, lastMessage}]}` **unbounded** |
| POST | `/conversations` | jobseeker/employer | `candidateId` (employer), `employerId` (jobseeker), `jobId` | 201 `{id, conversation: {id}}`; 403 not a party/not an applicant; 429 |
| GET | `/conversations/:id/messages` | participant | — | `{messages: [{id, senderId, body, createdAt, readAt}]}` last 200; marks read; non-party 404 |
| POST | `/conversations/:id/messages` | participant | `body` (trimmed, ≤ 5000) | 201 `{message}`; 422 blank; 429 |

### Acts and bookings

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/public/acts`, `/acts` | public / any | `q, city` | `{acts}` ≤ 100 (active; no owner id or riders) |
| GET | `/public/acts/:id` | public | — | `{act}`; inactive → 404 |
| GET | `/acts/:id` | any | — | owner/admin: full `api_json`; others: public view of active acts; foreign inactive → 404 |
| GET | `/acts/me` | talent | — | `{acts}` **unbounded** |
| POST | `/acts` | talent | `name, actType, tagline, bio, city, lineupSize, minFee, maxFee, currency, feeBasis, …, status, genres[]` | 201 `{id, act}`; `verified` ignored |
| PATCH/PUT/DELETE | `/acts/:id` | talent (owner) | as create | `{act}` / `{ok}` (DELETE deactivates) |
| POST | `/acts/:id/members` | talent (owner) | `displayName, roleName, instrument, userId (active jobseeker)` | 201 `{id}`; 400 status; 404 user; 409 duplicate |
| DELETE | `/acts/:id/members/:memberId` | talent (owner) | — | `{ok}`; 409 leader |
| GET | `/bookings` | talent | — | `{bookings: [… actName, requesterName, isOwner, isRequester, latestQuote, paidAmount, paymentCount]}` **unbounded** |
| POST | `/bookings` | talent | `actId, eventType, eventDate, city, budgetMin/Max, …` | 201 `{id}`; 409 own act; 402 plan |
| POST | `/bookings/:id/quote` | talent (act owner) | `performanceFee, travelFee, productionFee, otherFee, depositPercent, validUntil, …` | 201 `{id, total}`; 409 state |
| POST | `/bookings/:id/status` | party | `status` per owner/requester transition table | `{ok}`; 409 |
| POST | `/bookings/:id/payment-order` | requester | `Idempotency-Key` header | `{payment, checkout: {mode: mock\|razorpay, …}}`; 409/502/503 |
| GET | `/bookings/:id/payments` | party | — | `{payments}` |
| POST | `/booking-payments/:id/confirm` | payer | `orderId, paymentId, signature` (Razorpay) | `{ok}`; 409/422/502 |

### Workspaces and planning

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/organizations` | talent | — | `{organizations: [… memberCount, memberRole]}` **unbounded** |
| POST | `/organizations` | talent | `name, orgType, website, city, taxId, billingEmail` | 201 `{id}` |
| GET | `/organizations/:id/members` | member | — | `{members: [{id, name, email, role}]}`; non-member 404 |
| POST | `/organizations/:id/members` | owner/admin member | `email, role: admin\|recruiter\|booker\|finance\|member` | 201; 400 `INVALID_ROLE`; 402 seats; 403 |
| DELETE | `/organizations/:id/members/:userId` | owner/admin member | — | `{ok}`; 409 owner |
| GET | `/urgent-requests` | talent | `city, role` | `{requests: [… requesterName, requesterVerified, myResponse, responseCount]}` **unbounded, N+1** |
| POST | `/urgent-requests` | talent | `title, roleName, city, startAt, endAt, budgetMin/Max, …` | 201 `{id}` |
| PATCH/PUT | `/urgent-requests/:id` | requester | `status: filled\|cancelled` | `{ok}`; 400 |
| POST | `/urgent-requests/:id/respond` | talent (not requester) | `message, rate` | 201 `{ok}` (upsert) |
| GET | `/urgent-requests/:id/responses` | requester | — | `{responses: [{user_id, name, headline, message, rate, …}]}` |
| GET / POST | `/band-projects` | talent | `name, concept, city, genres[], commitmentType, …` | `{projects: [… roles]}` / 201 `{id}` |
| POST | `/band-projects/:id/roles` | talent (owner) | `roleName, instrument, countNeeded, skillLevel, requirements, compensation` | 201 `{id}` |
| POST | `/band-projects/:id/roles/:roleId/publish` | talent (owner) | — | 201 `{jobId, status}`; 402; 409 already published |
| GET / POST | `/crew-plans` | talent | `title, eventType, city, eventDate, audienceSize, budget, needs[]: music\|sound\|lighting\|production` | `{plans: [… roles]}` / 201 `{id, roles}` |
| POST | `/crew-plans/:id/convert` | talent (owner) | — | 201 `{projectId}` |

### Billing

| Method | Path | Auth | Params | Response / notes |
| --- | --- | --- | --- | --- |
| GET | `/billing/subscription` | any | — | `{subscription, plan, purchasedPlan}` |
| POST | `/billing/checkout` | talent | `planCode: pro\|studio\|enterprise`, `Idempotency-Key` | `{subscription, checkout}` or `{salesAssisted, message}`; 400; 409; 502/503 |
| POST | `/billing/cancel` | any | — | `{ok}`; 404 no subscription |
| POST | `/billing/webhook/razorpay` | Razorpay signature | raw body, `X-Razorpay-Signature` | `{ok, duplicate?}`; 401 bad signature; 503 unconfigured |

### Admin (role `admin`; everyone else 403, anonymous 401)

| Method | Path | Params | Response / notes |
| --- | --- | --- | --- |
| GET | `/admin/health` | — | `{ok, coreReady, optionalIntegrationsReady, checks, …}`; 503 not ready |
| GET | `/admin/stats` | — | `{stats: {users, jobseekers, employers, …}}` |
| GET | `/admin/tester` | — | `{summary, checks, generatedAt}` |
| GET | `/admin/users` | — | `{users}` ≤ 500 (≈560 KB with 500 users) |
| PATCH/PUT | `/admin/users/:id` | `status: active\|suspended\|pending` | `{ok}`; suspending revokes sessions; 409 self |
| POST | `/admin/users/:id/grant-plan` | `planCode: pro\|studio\|enterprise, days (clamped 1-366)` | 201 `{id}` |
| GET / PATCH/PUT | `/admin/jobs[/:id]` | `status: pending\|published\|rejected\|closed, note` | `{jobs}` ≤ 500 / `{ok}` |
| GET / PATCH/PUT | `/admin/reviews[/:id]` | `status: published\|rejected` | ≤ 500 |
| GET / PATCH/PUT | `/admin/verifications[/:id]` | `status: approved\|rejected` | `{requests}` ≤ 500; approval sets `profile.verified` |
| GET / PATCH/PUT | `/admin/reports[/:id]` | `status: resolved\|dismissed` | ≤ 500 |
| GET | `/admin/audit`, `/admin/subscriptions`, `/admin/billing-attempts`, `/admin/bookings` | — | ≤ 300 / 500 |
| POST | `/admin/billing-attempts/:id/reconcile` | — | `{attempt}`; 409 no provider id; 502 |
| POST | `/admin/search/reindex` | — | `{count, indexed, provider}` |

## Known gaps (tests skip with `OWNER:` until fixed)

Authorization/correctness: non-party booking status change returns 409 instead of 404; admin
reconcile is 500 when Razorpay is unconfigured; `POST /organizations {name: ""}` creates a
nameless workspace; portfolio updates require `type`; deleting a talent folder with members is
500. Type confusion (`?q[]=a`, `?city[x]=y`, `{actId: [..]}`, `{needs: "sound"}`) is 500 on jobs,
talent, acts, reviews, urgent requests, employer applications, conversations, bookings and crew
plans. N+1: `/urgent-requests` (~2 queries per row; 205 queries for 100 rows) and
`/talent-folders`. `fitScore` is read by JobSearch/JobDetails but only `/dashboard` returns it.
