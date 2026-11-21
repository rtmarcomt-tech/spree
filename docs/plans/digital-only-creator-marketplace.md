# Digital-Only Creator Marketplace

**Status:** Architecture plan — implementation not started  
**Target:** Custom Spree deployment, based on the existing 6.0 codebase  
**Branch:** `feat/digital-only-marketplace`  
**Purpose:** Adapt this Spree repository into a multi-creator marketplace selling individual digital photographs and videos only.

## Product contract

The following requirements are fixed for this implementation:

- Multiple creators, each with an independently managed profile and catalogue.
- Only individual photographs and videos are sold. No bundles, packs, physical products, shipping, inventory or subscriptions.
- A content item may be free or paid. Paid content is purchased individually.
- The platform receives buyer payments through the platform's own PayPal merchant account.
- The platform commission is **10% of each completed sale**.
- Creator earnings are recorded in a ledger. Funds remain unavailable for payout during a configurable holding period to cover refunds and disputes.
- A creator payout is eligible only when the creator's payable balance reaches a configurable minimum.
- PayPal is the payment method. **Do not introduce Stripe or Stripe Connect.**
- Creator registration/application, identity and content approval must be completed before publication. New or changed media remains private and unavailable until moderation approves it.
- Admin review must support approve, reject with reason, request correction, suspend and reinstate. Uncertain or risky automated moderation results require human review. Every decision is auditable and appealable.
- The platform controls the payment relationship with the buyer. A creator must never receive buyer payment credentials or access to another creator's orders, customers, files or ledger.
- No implementation may silently change these rules.

## Existing Spree capabilities confirmed in this repository

The repository already contains substantial reusable functionality:

1. **Digital delivery:** `Spree::DigitalAsset`, `Spree::DigitalLink`, private Active Storage attachments, download limits, signed download URLs, download events and customer download endpoints. The relevant implementation is in `spree/core/app/models/spree/digital_asset.rb`, `spree/core/app/models/spree/digital_link.rb`, `spree/core/app/workflows/spree/digital_assets/` and the Store/Seller API controllers.
2. **Seller marketplace:** seller identity, onboarding, seller-scoped APIs, seller product submission/review, commission rules, order splitting, payment splits and the two-level `SellerTransfer` / `SellerPayout` ledger.
3. **Seller files:** the Seller API already allows private digital-file uploads to a seller's own products, and can send an approved product back to review when its digital file changes.
4. **PayPal checkout:** the PayPal provider exists under `spree/providers/paypal`; it is a buyer checkout gateway, not a creator payout provider.
5. **Manual payout provider:** `Spree::PayoutProvider::System` records settlements without moving money. An operator can mark a payout complete after sending it externally.

These are source-level findings from the current `main` tree and its implementation plans. They are not a claim that the creator marketplace is already production-ready. The marketplace plan still records dashboard/onboarding work as outstanding, and its automated payout path is Stripe-specific.

## Important architectural distinction: PayPal checkout vs creator payouts

The existing PayPal gateway accepts buyer payments into the store's PayPal merchant account. It does not, by itself, pay creators.

The current core ledger has a provider contract for creator payouts. The first implementation must use the existing ledger and must not route money through Stripe. The initial operational design is:

- Buyer checkout: existing PayPal payment-session provider, with the platform's PayPal merchant credentials.
- Earnings: existing Spree commission and seller-transfer ledger, configured for a fixed 10% platform commission.
- Holding period: add an explicit release-eligibility rule to the ledger/sweep path; do not treat order fulfilment as immediate payout eligibility.
- Minimum payout: use the existing seller minimum payout threshold, with a store-level default and a controlled creator-level override only if supported by the existing model.
- Payout execution: initially use the existing System payout provider and the operator's PayPal account to send creator payouts, then record the PayPal transaction/reference and complete the payout. This avoids claiming that the checkout gateway automatically supports PayPal Payouts. A dedicated automated PayPal Payouts provider is a separate, gated extension and must only be implemented after confirming PayPal Payouts API access, recipient requirements, currencies, fees, limits, webhook semantics and idempotency behaviour.

No payout may be completed merely because a payout record was created. Completion must mean that the external PayPal payment was actually sent and confirmed. Unknown outcomes must remain unresolved and must never be retried blindly.

## Domain model and ownership

Reuse Spree's existing `Store`, `Seller`, `Product`, `Variant`, `DigitalAsset`, `DigitalLink`, `Order`, `OrderGroup`, `PaymentSplit`, `CommissionLine`, `SellerTransfer` and `SellerPayout` models where their contracts fit.

The catalogue will represent one purchasable content item per product, with one default variant and one approved digital asset. The product is the commercial listing (title, description, price, creator, visibility and publication status); the private digital asset is the original deliverable. A listing may be free or paid. Do not expose original storage URLs or blob identifiers.

Required ownership rules:

- Every creator-owned product and asset is scoped to exactly one approved seller.
- Every order line retains its seller attribution through checkout and order splitting.
- Every commission, transfer and payout is scoped to the seller and store.
- Every uploaded blob is private and store-owned.
- Creator APIs use seller-scoped controllers and current-seller lookups; never accept a client-supplied seller ID as authorization.
- Public catalogue endpoints return only approved, published listings and safe preview media.
- A buyer receives a download entitlement only for a free item or a successfully paid item.
- A creator can access only their own listing, media status, sales summaries and ledger rows.
- Admin users can review all creators, listings, media, orders, refunds, disputes and payout records according to RBAC.

## Content lifecycle

1. Creator applies/registers and submits required profile and verification information.
2. Admin reviews the creator. Rejected or pending creators cannot publish or sell.
3. Approved creator submits a content listing and uploads the original file to private storage.
4. Upload validation checks file signature/type, size, duration/dimensions where relevant, malware scan and moderation state. The original remains private.
5. Automated moderation may approve only clear low-risk cases under a documented policy. Uncertain, flagged or high-risk content is blocked pending human review.
6. Admin approves or rejects the listing/media. Rejection records a reason and correction/appeal path.
7. Approved content may be published as free or assigned an individual price.
8. A change to the original file or material listing content returns it to review and removes it from sale until re-approved.
9. Suspension of a creator blocks new publication and new sales; existing purchase entitlements and financial records remain auditable and are handled under a documented support/refund policy.

## Purchase and delivery lifecycle

### Free content
- Buyer selects one free listing.
- The platform creates a free order/entitlement without a PayPal charge.
- A unique, authorized digital link is issued to the buyer.
- Access is checked against the buyer's entitlement and the asset's current availability.
- Free downloads do not create commission or creator earnings.

### Paid content
- Buyer purchases one listing at a time or multiple independent listings in one cart only if the existing Spree order-splitting rules preserve creator ownership and each item remains independently priced. No bundle or subscription semantics.
- PayPal payment is created against the platform merchant account.
- The order is not considered paid until the payment-session completion contract confirms it.
- The existing order split and payment split logic must preserve the creator attribution for each line.
- A purchase entitlement and digital link are issued only after successful payment/order completion.
- Failed, pending, cancelled, refunded or disputed payments must not grant new access. Existing access after refund/dispute follows an explicit policy and must be revocable where legally and operationally required.
- Delivery uses private storage and short-lived signed URLs. Never expose public bucket URLs.

## Commission, holding period and creator balance

- Commission rate is fixed at 10% for every creator and product in the initial release. Do not expose seller-editable commission rates.
- Calculate money with `BigDecimal` and Spree's money helpers; never use floating-point arithmetic.
- The 10% commission must be represented by Spree's commission records and remain traceable per order line.
- Creator gross earnings, platform commission, refunds, reversals, payable balance and completed payouts must be separately auditable.
- The hold period is configurable at store level. A transfer may be included in a payout only after its release timestamp has passed and the underlying buyer payment is settled and not under a blocking dispute/refund state.
- Refunds and chargebacks during the hold period reduce or cancel the creator's pending earnings before release.
- A refund or dispute after payout must create a compensating ledger event; never rewrite or delete a completed transfer or payout.
- The minimum payout amount is configurable. Below the threshold, eligible funds carry forward; no payout is created.
- The payout sweep must be idempotent and concurrency-safe. A transfer cannot be included in more than one payout.
- Payout completion requires an external PayPal payment reference and confirmation. Failed and ambiguous outcomes must be represented distinctly; ambiguous outcomes are not automatically retried.

## Media security and moderation

- Originals are private at rest and are delivered only through authorized, expiring links.
- Preview media is generated as a separate derivative with appropriate watermarking/resolution policy; it must not reveal the original.
- Validate the actual file signature, not just the filename or client MIME type.
- Apply upload size, duration, image dimension and allowed-format limits.
- Run malware scanning and media moderation before publication.
- Store moderation state, decision, reviewer/automation source, timestamps, reason codes and appeal history.
- Default to blocked/private when scanning or moderation fails, times out or returns an uncertain result.
- Prevent unapproved content from appearing in public APIs, search, feeds, sitemaps, social previews or CDN caches.
- Audit access to sensitive originals and administrative moderation actions.
- Define retention/deletion rules without destroying financial or legal audit records.

## Application surfaces

### Public storefront
- Creator discovery and approved creator profiles.
- Search/browse approved content.
- Individual content detail pages with safe preview.
- Free access or individual paid checkout.
- Buyer account, purchase history and downloads.

### Creator area
- Application and verification status.
- Profile editing subject to review.
- Content submission and private upload.
- Moderation status, rejection reason and resubmission.
- Free/paid choice and individual price.
- Sales, earnings, held balance, eligible balance and payout history.
- No access to buyer payment credentials or other creators' data.

### Admin
- Creator application and verification queue.
- Content/media moderation queue with audit trail and appeals.
- Creator suspension/reinstatement.
- Listings and publication controls.
- Orders, PayPal payment state, refunds and disputes.
- Commission and ledger reporting.
- Held/eligible balances, minimum payout configuration and PayPal payout queue.
- Manual payout completion with external PayPal reference.
- RBAC for each administrative action.

## Implementation waves and acceptance gates

### Wave 0 — source audit and architecture freeze
- Inspect current models, migrations, workflows, API controllers, serializers, RBAC, jobs, dashboard routes, SDKs, tests and upgrade constraints.
- Confirm exact current behavior of seller onboarding, seller product review, digital asset lifecycle, free products, order completion, refunds, commission calculation, payment splits and payout sweeps.
- Identify every Stripe-only code path and ensure no Stripe dependency is required by the target deployment.
- Produce a dependency map and test matrix before implementation.

**Gate:** no unresolved ownership, payment, refund, moderation or payout state transitions.

### Wave 1 — digital-only commerce boundary
- Enforce digital delivery profiles for all marketplace listings.
- Remove physical shipping, stock reservation, carrier selection and physical fulfilment from creator and buyer journeys.
- Restrict content types to photographs and videos for the initial release.
- Enforce one purchasable content item per listing, with one default variant and one digital asset.
- Preserve Spree's internal fulfillment/order contracts where required, but expose no physical-commerce UI or API paths to marketplace users.

**Gate:** no checkout path asks for a shipping address or invokes physical shipping/inventory.

### Wave 2 — creator onboarding and approval
- Complete the end-to-end creator application, verification, approval, rejection, correction, appeal and suspension paths.
- Ensure seller identity, roles, JWT audience, tenant scope and RBAC are consistent.
- Complete creator-facing onboarding UI and admin review UI.

**Gate:** unapproved creators cannot publish, upload saleable media or receive sales.

### Wave 3 — media and content moderation
- Complete private uploads, file validation, derivative previews, moderation workflow, audit records and appeals.
- Ensure seller digital-asset writes pass through the existing digital-asset workflows and seller rules.
- Add human review for uncertain/high-risk results and fail-closed behavior.

**Gate:** no unapproved original or preview is publicly accessible, indexed or purchasable.

### Wave 4 — catalogue, free access and paid purchase
- Implement one-listing/one-content semantics and free/paid state.
- Integrate PayPal checkout using the existing provider and platform credentials.
- Preserve creator ownership through cart, order split and payment split.
- Issue secure entitlements and downloads only under the purchase rules above.

**Gate:** test the complete creator-to-buyer path for free and paid content, including failed and delayed PayPal outcomes.

### Wave 5 — commission, hold and payouts
- Configure the commission engine to exactly 10%.
- Add hold/release eligibility without bypassing the existing two-level ledger.
- Enforce minimum payout thresholds and creator/store settings.
- Use the System payout provider for the initial operator-confirmed PayPal payout workflow unless automated PayPal Payouts is separately approved and technically verified.
- Add refunds, reversals, ambiguous provider outcomes and idempotency tests.

**Gate:** every cent is explainable from buyer payment through commission, creator earnings, hold, payout and refund/reversal.

### Wave 6 — end-to-end validation and deployment
- Complete API, model, workflow, job, dashboard, SDK and Playwright coverage.
- Validate role/tenant isolation and private media access.
- Test concurrent purchases, duplicate webhooks, duplicate sweeps, upload failures, moderation failures, refund/dispute races and payout retries.
- Prepare environment configuration, backups, migrations, deployment and rollback instructions for the target VPS.

**Gate:** no feature is considered complete until its full creator → content → moderation → listing → purchase → entitlement → delivery → ledger → payout lifecycle passes.

## Required test scenarios

1. Pending/rejected creator cannot publish, upload saleable content or receive orders.
2. Approved creator can submit a photograph and a video; each stays private until approval.
3. Wrong file signature, disallowed type, oversized file, malware result or moderation uncertainty blocks publication.
4. Admin approval publishes; rejection records a reason; correction and appeal return to review.
5. Replacing an approved file reopens moderation and prevents sale/delivery of the unapproved replacement.
6. Free content grants an entitlement without a payment or commission.
7. Paid content cannot grant an entitlement before PayPal payment completion.
8. PayPal cancellation, decline, pending capture, duplicate webhook and webhook replay do not double-charge or grant unauthorized access.
9. Creator A cannot access creator B's products, files, orders, buyers, transfers or payouts by guessing IDs.
10. A sale generates exactly 10% platform commission and the correct creator earning.
11. Earnings remain held until both the hold period expires and payment/dispute conditions allow release.
12. Refund before release cancels/reduces pending earnings; refund after payout creates a compensating ledger entry.
13. Below-minimum eligible balance creates no payout; reaching the threshold creates exactly one payout.
14. Duplicate or concurrent payout sweeps cannot settle the same transfer twice.
15. Payout completion requires a PayPal reference; failed and unresolved outcomes remain recoverable without duplicate payment.
16. No buyer or creator journey exposes physical shipping, carrier selection, stock reservation or subscription purchase.
17. Private originals cannot be accessed without a valid entitlement and authorized digital link.

## Explicit non-goals for the first release

- Physical products, shipping, stock management and warehouse operations.
- Subscription billing, memberships, recurring payments, bundles or content packs.
- Creator-to-buyer messaging.
- Stripe, Stripe Connect or any Stripe dependency.
- Automated PayPal Payouts until the separate PayPal Payouts API prerequisites are confirmed.
- License-code pools, external entitlement providers and third-party content delivery providers.
- Unreviewed AI-only moderation.

## Repository implementation rules

- Work only on `feat/digital-only-marketplace`; never commit directly to `main`.
- Preserve the upstream Spree architecture and existing contracts unless a documented marketplace requirement requires a change.
- Follow the adjacent `AGENTS.md` rules in every touched area.
- Reuse existing workflows, APIs, serializers, registries, jobs, SDKs and UI components before adding new abstractions.
- Every seller/admin API change must include RBAC, serializers, SDK generation where applicable, and tests.
- Every buyer/creator-visible behavior change must include Playwright coverage.
- Do not edit generated API specs, generated SDK types or generated files by hand.
- Do not introduce physical product features into the creator-facing product surface.
- Do not add Stripe as a fallback.
- Keep changes in small, reviewable commits on the feature branch. Open a pull request only after the required code and security reviews.

## Current open technical verifications

1. Confirm how this branch currently represents zero-priced products and whether the Store API can grant a free digital entitlement without creating a PayPal payment.
2. Confirm the exact payment/settlement state that should gate creator transfer release.
3. Confirm whether PayPal Payouts API is enabled for the platform merchant account and whether the business intends manual or automated creator payments. Until confirmed, use the existing System provider for operator-confirmed PayPal payouts.
4. Confirm legal/compliance requirements for creator identity verification, age/rights verification, content moderation, retention and chargeback handling before production launch.
