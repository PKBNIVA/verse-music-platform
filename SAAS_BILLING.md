# Verse SaaS Billing Architecture

## Commercial model
- Candidate/professional core: free profile, discovery and applications.
- Starter: low-volume hiring/booking.
- Pro: active band/manager/small-team workflow.
- Studio: labels, studios, agencies and production teams.
- Enterprise: sales-assisted, custom seats/limits/invoicing.

## What is metered
Server-enforced limits: active opportunities, saved-talent capacity, concurrent booking enquiries and workspace seats. Never gate a candidate's right to apply behind payment.

## Trial lifecycle
`pending` means checkout/mandate not yet authenticated and grants only Starter entitlements.
`trialing` means gateway authorization succeeded and trial entitlements are active.
`active` means recurring billing is active.
`past_due/paused/cancelled/expired` do not grant paid capacity unless an explicit grace policy is later added.

Only the first paid-plan activation for an account receives the standard free trial; changing plan should not create infinite trials.

## Razorpay integration
Server creates subscriptions. Browser receives only checkout-safe identifiers. Signed webhooks are the subscription source of truth. Duplicate events are de-duplicated using Razorpay event IDs. Client checkout success never directly grants entitlements.

## Booking payments
Booking deposits use server-created Orders, not subscription objects. The server verifies checkout signatures and also reconciles payment webhooks. Booking payments have their own ledger.

## Production requirements still needed
GST/invoicing, dunning, annual plans, proration, refunds, settlement/KYC, finance exports, chargebacks, reconciliation jobs, immutable accounting ledger and a support tool for safe subscription recovery.

## Cancellation and plan-change safety
A Verse cancellation is not merely a local flag. For a live Razorpay subscription the backend calls the provider cancellation endpoint. Active billing cycles are scheduled for cycle-end cancellation; subscriptions without an active cycle may require immediate cancellation. Verse blocks creation of a different paid plan while another recurring mandate is active/pending so a customer is not accidentally charged twice.

Pending authorization does not unlock paid entitlements. A customer can resume the same pending checkout instead of creating another subscription. The first eligible paid plan can receive its configured free trial; subsequent paid subscriptions do not automatically receive another trial.
