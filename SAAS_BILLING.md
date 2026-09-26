# Verse SaaS Billing Architecture

## Commercial model
- Candidate/professional core: free profile, discovery and applications.
- Starter: low-volume hiring/booking.
- Pro: active band/manager/small-team workflow.
- Studio: labels, studios, agencies and production teams.
- Enterprise: sales-assisted, custom seats/limits/invoicing.

## What is metered
Server-enforced limits (`Entitlements`): active opportunities, saved-talent capacity, concurrent booking enquiries and workspace seats. Never gate a candidate's right to apply behind payment.
A refused action returns HTTP 402 with code `PLAN_LIMIT_REACHED` (shortlists, bookings) or `PLAN_LIMIT` (jobs, band-project roles, seats). The web app shows an app-wide "Plan limit reached" dialog with a "See plans" link for either code.

## Trial lifecycle
`pending` means checkout/mandate not yet authenticated and grants only Free entitlements.
`trialing` means gateway authorization succeeded and trial entitlements are active.
`active` means recurring billing is active.
`past_due/cancelled` do not grant paid capacity unless an explicit grace policy is later added.

Only the first paid-plan activation for an account receives the standard free trial; changing plan should not create infinite trials.

## Razorpay event → local status

| Razorpay webhook | Local status | Billing page |
| --- | --- | --- |
| `subscription.authenticated` | `trialing` (trial still running) or `pending` | Free trial, first charge date |
| `subscription.activated`, `subscription.charged`, `subscription.resumed` | `active` (+ `current_period_start/end` from the entity) | Active, next charge date |
| `subscription.pending` (renewal failed, retrying), `subscription.halted`, `subscription.paused` | `past_due` | Payment failed, paid features paused |
| `subscription.cancelled`, `subscription.completed` | `cancelled` | Cancelled, back on Free |
| `payment.captured` / `payment.failed` | booking deposit `paid` / `failed` | Deposit paid · booking confirmed / decline + retry |
| `refund.processed` (full) | booking deposit `refunded` | Deposit refunded |

Events are de-duplicated by `X-Razorpay-Event-Id`, ordered by the event's `created_at`
(older events are recorded as `stale`), and a status only moves along allowed transitions.
Every processed event is stored in `billing_events` (admin: `GET /api/admin/billing-events`,
`GET /api/admin/billing-events/:id`).

## Razorpay integration
Server creates subscriptions. Browser receives only checkout-safe identifiers (`keyId`, `subscriptionId` / `orderId`, server-computed amount and currency). Plan, amount and currency are never read from the client. Signed webhooks are the subscription source of truth. Client checkout success never directly grants entitlements; the Billing page polls until the webhook has been applied.

`GET /api/billing/subscription` returns `summary` (status, `nextChargeAt`, `accessEndsAt`), `history` (subscription charges from webhooks) and `testMode` (boolean only; keys are never exposed).

## Booking payments
Booking deposits use server-created Orders, not subscription objects. Order receipts are `dep_<payment uuid>` (Razorpay's 40-character limit). The server verifies checkout signatures and the captured payment with Razorpay, and also reconciles payment webhooks. Confirmation is idempotent: when the `payment.captured` webhook wins the race, the checkout confirmation of the same verified payment succeeds instead of reporting a conflict. Booking payments have their own ledger.

## Reconciliation
`BillingReconciliationJob` (every 30 minutes) resolves attempts left `pending`/`ambiguous` by crashes, timeouts and 5xx responses. With a provider id it fetches the resource; without one it looks the resource up by what Verse sent (`notes.attempt_id` on subscriptions, the receipt on orders) and attaches it. Attempts confirmed absent at Razorpay are failed after 30 minutes and release their local reservation. Admins can reconcile one attempt with `POST /api/admin/billing-attempts/:id/reconcile`.

## Cancellation and plan-change safety
A Verse cancellation is not merely a local flag. For a live Razorpay subscription the backend calls the provider cancellation endpoint:

- **active** paid plan: cancelled at cycle end; access continues until `current_period_end`, then `subscription.cancelled`/`completed` ends it.
- **trialing** or **past_due**: cancelled immediately (nothing is owed for the current period); paid features stop at once. The confirmation dialog says so.
- **pending** (never authorised) mandates: cancelled immediately.

Verse blocks creation of a different paid plan while another recurring mandate is active/pending so a customer is not accidentally charged twice (`PLAN_CHANGE_REQUIRES_CANCELLATION`).

Pending authorization does not unlock paid entitlements. A customer can resume the same pending checkout ("Complete setup") instead of creating another subscription. The first eligible paid plan can receive its configured free trial; subsequent paid subscriptions do not automatically receive another trial.

## Local simulator
`RAZORPAY_SIMULATOR=true` with an `rzp_test_` key (development/test only, refused in production and with live keys) routes all Razorpay API calls to `RazorpaySimulator` and swaps checkout.js for a simulated modal. See DEPLOYMENT.md → "Local rehearsal without credentials". Rails integration tests (`razorpay_simulator_flows_test.rb`) and Playwright (`tests/e2e/payments-simulator.spec.ts`) exercise the complete flows against it, including duplicate/out-of-order webhooks, declines, refunds and lost create responses.

## Go-live
The exact Railway ← Razorpay dashboard mapping, webhook events, capture setting and test-mode rehearsal are in DEPLOYMENT.md → "Payments (Razorpay) go-live checklist".

## Production requirements still needed
GST/invoicing, dunning emails, annual plans, proration, partial refunds in the ledger, settlement/KYC, finance exports, chargebacks, immutable accounting ledger and a support tool for safe subscription recovery. Payment attribution for subscription `payment.failed` events without a local order (recorded with no user).
