# Digital-Only Creator Marketplace — Implementation Blueprint

**Status:** Implementation in progress — partial; integration validation remains outstanding  
**Branch:** `feat/digital-only-marketplace`  
**Parent architecture:** `docs/plans/digital-only-creator-marketplace.md`

This blueprint translates the source audit into one coherent implementation design. It is intentionally end-to-end: creator onboarding, immediate media publication, post-publication enforcement, checkout, delivery, earnings, holds, refunds and manual payouts are treated as one lifecycle.

## 1. Deployment boundary and fixed product rules

- One Spree Store is the marketplace tenant.
- Many approved creators are represented by Spree Sellers.
- Only photo and video content may be listed.
- One product represents one individually purchasable content item. One default variant, one zero-or-positive price per supported currency, one required original asset.
- A cart may contain multiple individually priced listings. No bundles, packs, subscriptions or recurring billing.
- Free items use a zero-valued Spree Price and the zero-total order path; they never create a PayPal payment session.
- Paid items use the platform's PayPal merchant account. Capture at checkout is the required store configuration for the initial release.
- Commission is 10% of the approved commission basis. The exact tax/discount treatment follows Spree's tax-aware commission calculation and must be configured and tested, not recomputed separately.
- Creator payouts are manual PayPal transfers in the first release, recorded with the external PayPal transaction reference. The PayPal checkout gateway is not a payout provider.
- No Stripe or Stripe Connect dependencies.
- Creator applications and verification evidence remain private until seller approval. Creator media is published immediately after upload by an approved seller; there is no per-file pre-approval.
- Physical fulfilment, shipping, package types, stock locations, inventory and shipping addresses are not part of the product experience.

## 2. Existing entities to reuse

| Existing entity | Marketplace responsibility |
|---|---|
| `Spree::Store` | Marketplace tenant, currencies, PayPal credentials and store-level preferences |
| `Spree::Seller` | Creator identity, account status, team and creator profile |
| `Spree::SellerRequirement` / Submission | Creator checklist and reviewed evidence |
| `Spree::Product` | One content listing, title, description, status and channel publication |
| `Spree::Variant` / `Spree::Price` | Single purchasable option and zero-or-positive price |
| `Spree::DigitalAsset` | Private original media file |
| `Spree::DigitalLink` | Per-purchase download entitlement/token |
| `Spree::Cart`, `Order`, `OrderGroup` | Buyer cart, purchase record and multi-creator order split |
| `Spree::PaymentSession`, `Payment`, `PaymentSplit` | PayPal checkout and seller share of a grouped payment |
| `Spree::CommissionRate`, `CommissionLine` | Immutable 10% commission calculation per sale |
| `Spree::SellerTransfer` | Creator earning and refund-reversal ledger |
| `Spree::SellerPayout` | Batch settlement of eligible creator earnings |
| `Spree::Refund` | Refund record and external PayPal credit operation |

Do not create parallel Creator, Listing, Purchase, Download or Wallet models where these existing models already express the same responsibility.

## 3. New persistence required

### 3.1 Store preferences

Add validated, store-scoped preferences:

- `creator_earnings_hold_days` — integer, minimum 0, default chosen by marketplace operations before launch.
- `creator_minimum_payout_amount` — reuse the existing default minimum payout preference rather than introduce a second source of truth.
- `creator_commission_rate` — do not expose as a mutable runtime preference; seed/enforce the enabled marketplace percentage rate at 10%.
- `creator_allowed_media_types` — server-side photo/video allowlist, narrower than the existing general seller digital-file allowlist.
- `creator_max_image_bytes`, `creator_max_video_bytes`, `creator_max_video_seconds`, `creator_max_image_dimension` — operational upload limits.
- `creator_preview_policy` — versioned policy for preview dimensions, watermarking and video preview duration.
- `creator_manual_payouts_enabled` — true for first release.

PayPal capture-at-checkout is configured through the existing payment-method capture setting. The marketplace must validate this configuration during deployment/health checks and warn or refuse launch if PayPal is configured for authorization-only capture.

### 3.2 Post-publication removal audit record

Use `Spree::DigitalAssetModeration` as an append-only record only when an administrator removes a published DigitalAssetVersion:

- `digital_asset_id` — required FK.
- `version` — monotonically increasing asset file version.
- `decision` — `removed`.
- `source` — `automated`, `human`, `system`.
- `decision_code` and `decision_note`.
- `submitted_by_id`, `reviewed_by_id`.
- `submitted_at`, `scanned_at`, `reviewed_at`.
- `scanner_name`, `scanner_version`, `scanner_result` JSON.
- `appeal_status`, `appeal_note`, `appealed_at`, `appeal_reviewed_by_id`, `appeal_reviewed_at`.

Removal records are append-only. A creator upload creates a new published version immediately; it does not create a moderation row.

### 3.3 Media file version

Add `Spree::DigitalAssetVersion`:

- `digital_asset_id`, `version`, `active_storage_blob_id` (private blob).
- `content_type`, `byte_size`, `checksum`, `filename`.
- `status`: `published`, `removed`.
- `created_by_id`, timestamps.

The DigitalAsset's current attachment may continue to represent the latest candidate for compatibility, but delivery resolves the approved version for the entitlement, not an arbitrary current attachment. If retaining prior approved originals is required for existing purchases, old blobs cannot be purged while an active entitlement references them.

### 3.4 Creator earning holds

Add `Spree::SellerTransferHold`:

- `seller_transfer_id` — required FK.
- `kind` — `refund_review`, `dispute`, `manual_review`, `compliance`.
- `status` — `active`, `released`.
- `source_reference` — refund/dispute/admin case reference.
- `reason`, `created_by_id`, `released_by_id`, `released_at`.
- `metadata` JSON and timestamps.

Add `release_at` to `Spree::SellerTransfer`. The standard hold date is set once when the earning is created: `order.fulfilled_at + creator_earnings_hold_days`. Do not recompute historical release dates when the store preference changes.

A transfer is payout-eligible only when:
1. transfer is an earning, status is completed, and payout_id is null;
2. release_at is at or before the current time;
3. the order's captured/net-captured share covers the payable sale amount;
4. there is no active SellerTransferHold;
5. there is no refund in requested/processing state for that order/payment share;
6. there is no open dispute/chargeback hold;
7. the seller remains approved and payouts are enabled.

Refund reversals remain negative ledger entries and are included in the same payout batch logic as today.

## 4. State machines and authorization

### 4.1 Creator lifecycle

`pending → invited → onboarding → ready_for_review → approved`

Other terminal/exception states: `rejected`, `suspended`, `canceled`.

Reuse Spree seller workflows and JWT audience isolation. Creator approval must require the marketplace-specific requirement checklist. Do not allow the operator's override option in the normal UI; any exceptional override must require a high-privilege role and an explicit audit reason.

Creator checklist:
- Accept creator agreement and marketplace policies.
- Complete profile.
- Provide legal/billing identity details.
- Complete identity and age verification (document submission plus human verification or an approved external verification service).
- Submit rights ownership/licensing attestation for every content item.
- Submit consent/release evidence for every identifiable participant where required by the marketplace's policy.
- Complete manual review.
- Publish at least one approved content item if minimum content count is retained.

Remove default `ReturnsAddress`, `DeliveryMethod` and `PackageType` requirements from this store. They are physical-shipping requirements. Keep billing identity/address where needed for legal invoicing. The existing Document/OperatorReview/Attestation requirement types are workflow primitives only; they do not prove document authenticity or age.

### 4.2 Content lifecycle

`draft → proposed → approved/published → archived`

Separate media lifecycle:
`uploaded → pending_scan → pending_review → approved`
or
`uploaded → pending_scan → rejected/quarantined`.

Publication requires all gates:
- creator approved and sellable;
- product listing approved and active;
- required original and preview media versions approved;
- product has the required digital delivery profile and exactly one eligible digital asset.

A content edit affecting title, price or description may reopen listing review according to policy. Replacing an original or preview creates a new media version and publishes it immediately. The administrator may remove the new version if it violates platform rules.

### 4.3 Post-publication enforcement

- Scanner clean and low-risk: move to `pending_review` or `approved` only according to an explicit approved policy; default launch setting is human approval.
- Malware, invalid signature, disallowed type or policy violation: `rejected` or `quarantined`.
- Scanner timeout, unavailable scanner or uncertain result: remain blocked in `pending_scan` / `pending_review`.
- Human approve: `approved`.
- Human reject: `rejected` with mandatory reason.
- Creator appeal: create an appeal record; never rewrite the original decision.
- Appeal reviewer: approve, uphold rejection or request additional evidence.

All state changes publish domain events and write audit records.

## 5. Public availability predicate

Create one service, e.g. `Spree::CreatorMarketplace::Availability`, that returns whether a product is eligible for public display and purchase. It must be used by:

- Store product collection and single-resource lookup by slug or prefixed ID.
- Database search and product filter/facet endpoints.
- Meilisearch result intersection and filter counts.
- Product serializer preview URLs.
- Cart add/update and cart completion.
- Order completion and DigitalLink authorization/delivery.
- Sitemap, feed, social metadata and cache generation.

Predicate:
- product belongs to current store and current channel publication;
- product status active and available in current currency;
- seller exists and `seller.sellable?`;
- all required assets have a current approved version;
- preview derivative is approved and safe for public display;
- product is not quarantined, archived or withdrawn.

The database predicate is authoritative. Search-index documents and caches are accelerators, never the security boundary. On seller suspend/reject/holiday and media moderation transitions, invalidate relevant product caches and enqueue index updates/removals. Meilisearch facets must not expose counts for hidden sellers or media.

## 6. Upload, preview and secure delivery

1. Creator requests an upload target through the seller-scoped API. The server derives `current_seller` and product ownership.
2. Upload goes to private storage only.
3. Server checks signed blob ownership, actual file signature, MIME allowlist, file size, image dimensions, video duration/codec and checksum.
4. Malware scan runs asynchronously. No public endpoint can fetch the original at this stage.
5. A media moderation record is created for the version.
6. Preview generation runs in a separate worker. Image preview is resized/watermarked; video preview is a limited-duration, lower-resolution derivative with watermark. Preview also passes moderation.
7. Admin approves the original version and preview derivative. Only then may the listing become publicly available.
8. Paid purchase completion creates/retains the Spree DigitalLink entitlement. Free claim does the same through zero-total checkout.
9. DigitalLink authorization checks customer/order entitlement, product/seller state and the exact approved asset version. Deliver via short-lived signed private-storage URL.
10. Every denial, successful download and administrative access is auditable.

Do not expose Active Storage blob IDs, signed blob upload URLs, permanent storage URLs or original URLs in public serializers. Public preview URLs must point only to derivatives.

## 7. Buyer purchase and entitlement workflows

### Free content

- Price amount is exactly zero for the active currency.
- Buyer clicks “Get free content”.
- Create/complete a zero-total Spree cart/order; do not create a PayPal PaymentSession.
- Existing Digital fulfillment auto-fulfills and creates one DigitalLink per quantity.
- Link is visible in the authenticated buyer downloads library.
- No CommissionLine fee and no positive SellerTransfer earning are created.
- Repeated claim is idempotent and must not create duplicate entitlements.

### Paid content

- Buyer cart can contain multiple independent content products.
- Before creating the PayPal session, revalidate every product using the public availability predicate.
- PayPal payment session is created for the positive cart total with platform merchant credentials.
- PayPal capture-at-checkout is required. A session authorization or pending capture is not proof of settled funds.
- Payment session completion/webhook is idempotent. Order placement and seller order splitting preserve each line's seller.
- Digital links are generated only after the order has been completed through the valid payment path.
- The link cannot be used by another customer and cannot resolve to a non-approved media version.

### Payment states

- `Payment.completed?` / captured funds: eligible to start the hold clock once the order is fulfilled.
- Authorization-only / pending / requested: not payout-eligible.
- Failed / void / canceled: not payout-eligible.
- Refund requested: create/retain a transfer hold until the refund completes or fails.
- Refund completed: existing reversal subscriber writes a compensating transfer; the hold can be released only after the resulting ledger state is reconciled.
- Chargeback/dispute: no native dispute model or dispute webhook is present in the inspected Spree/PayPal code. First release therefore requires an admin-managed dispute case/hold with an external PayPal case reference. Automated PayPal dispute webhooks are a separately gated integration and must not be implied as already supported.

## 8. Commission and payout workflows

### Commission

- Seed one enabled percentage CommissionRate at 10% for the store.
- Remove/disable seller/product/category-specific commission override surfaces for this deployment.
- Validate configuration at boot/health check and block sales if the default rate is absent, disabled or not 10%.
- Continue using `CommissionOrder` and `CalculateLine`; do not implement parallel percentage arithmetic.
- Free order commission is zero; skip positive earning creation for a zero net seller amount.
- Persist CommissionLine exactly once at order placement. Never rewrite historical commission lines.

### Earning

- Existing `order.fulfilled` subscriber remains the event entry point.
- The seller transfer workflow creates the ledger earning idempotently.
- The System payout provider may mark the earning ledger row completed because it means “recorded as owed”, not “money paid”.
- Set `release_at` from the order's actual fulfilment timestamp and the configured hold duration.
- If the underlying buyer payment is not captured, retain the earning but prevent payout.
- If a refund is requested or dispute/manual hold is opened, create an active SellerTransferHold.

### Payout

- Reuse `SellerPayouts::SweepDueJob`, `SweepSellerJob`, `Sweep`, and the existing minimum threshold.
- Modify transfer collection to select only release-eligible earnings and completed reversals.
- Recheck all eligibility conditions inside the transaction immediately before claiming transfers.
- Keep the existing atomic `payout_id` claim and restatement behavior.
- The first release uses the System payout provider. Admin sees the eligible payout queue, sends the payment through the platform PayPal account, enters the PayPal transaction/reference, and completes the payout only after confirming the external movement.
- A payout with unknown external outcome remains `unresolved`; it cannot be retried until reconciled against PayPal.
- Do not build automated PayPal Payouts until the platform PayPal account's API eligibility, recipient onboarding, fees, limits, currencies, idempotency and webhook semantics are verified.

## 9. API and dashboard surface changes

### Public Store API

- Product list/detail: only available approved content; safe preview only; no original asset fields.
- Seller list/detail: only approved and sellable creators.
- Free claim: authenticated customer endpoint/action using the standard cart/order flow.
- Downloads: authenticated library plus token endpoint; token endpoint rechecks entitlement and approved version.

### Seller API

- Keep seller JWT audience and current-seller scope.
- Replace physical product create/update contract with creator content fields.
- Add media upload/version/status endpoints.
- Add creator appeals endpoint.
- Earnings and payouts remain read-only to creators.
- Remove or refuse delivery methods, package types, stock locations, shipping, physical inventory and physical fulfillment endpoints for creator roles.

### Admin API

- Creator review and identity/age evidence review.
- Content listing review.
- Media moderation queue, file version review and appeal decisions.
- Quarantine/reinstate and audit trail.
- Dispute case and earning hold management.
- Commission configuration read-only/guarded at 10%.
- Held vs eligible earnings, payout queue and manual PayPal reference completion.

### Seller dashboard

Reuse existing seller auth, route shell, profile/team, onboarding, product list, earnings and payout components. Replace product form with:
- content title and description;
- photo/video selection and metadata;
- private original upload;
- preview generation status;
- free/paid selector and price;
- moderation status, reviewer note and appeal action.

Remove delivery method, package type, stock location, shipping, inventory and physical fulfillment navigation.

### Admin dashboard

Add/extend:
- creator verification queue;
- content review queue;
- media moderation and appeal queue;
- disputes/holds;
- earnings release/hold visibility;
- manual PayPal payout queue with external reference.

## 10. Migration and implementation order

1. **M0 — Architecture freeze:** approve schema, states, API contracts, role matrix, and acceptance matrix. No feature code.
2. **M1 — Domain foundation:** preferences, DigitalAssetVersion, DigitalAssetModeration, SellerTransfer.release_at and SellerTransferHold; migrations and model specs.
3. **M2 — Digital-only guardrails:** listing validations, public availability service, seller sellability filter, free/paid product rules, shipping/stock API denial.
4. **M3 — Creator onboarding:** replace physical checklist, add identity/age/rights requirements, review and appeal surfaces.
5. **M4 — Media pipeline:** private uploads, file inspection, malware scanning integration, previews, moderation, version-aware delivery.
6. **M5 — Commerce:** free claim, PayPal capture configuration, paid checkout, split orders, entitlements, public previews and buyer downloads.
7. **M6 — Ledger:** fixed 10% commission configuration, release_at, payment capture gate, refund holds, dispute/manual holds, release-eligible sweep and minimum threshold.
8. **M7 — Operations UI:** admin moderation, dispute/hold management, PayPal payout queue and creator earnings display.
9. **M8 — Hardening:** end-to-end tests, cache/index invalidation, security tests, migrations, rollback and deployment.

Every wave is delivered as a coherent, tested unit on this feature branch. Do not merge partially working creator flows.

## 11. Mandatory acceptance matrix

- Creator lifecycle: pending, incomplete, approved, rejected, suspended, reinstated.
- Requirement checklist: no shipping/package/returns-address blockers; required identity/age/rights evidence reviewed.
- Media: photo, video, invalid signature, oversized file, unsupported codec, malware, timeout, uncertain moderation, reject, appeal, replacement, old-version entitlement.
- Visibility: hidden seller, suspended seller, holiday seller, proposed product, archived product, unapproved asset, quarantined asset; test list, detail slug, detail ID, search, facets, sitemap, cache, cart replay and checkout.
- Free: zero price, no PayPal session, one entitlement, no commission or payout earning, duplicate claim.
- Paid: PayPal capture success, capture pending, authorization-only, decline, cancel, timeout, duplicate webhook, delayed webhook, wrong amount/currency, split basket.
- Delivery: cross-customer token use, expired token, download limit, seller suspension, asset quarantine, signed URL expiry.
- Ledger: exact 10%, currency rounding, release timestamp, captured payment gate, hold duration change, minimum payout, concurrent sweeps, refund requested/completed/failed, refund before earning subscriber, refund after payout, unresolved payout.
- Dispute: manual hold opened/released; payout sweep cannot claim a held transfer.
- Isolation: creator A cannot access creator B's profile-private data, assets, orders, buyers, earnings, holds or payouts.
- Digital-only: no shipping address, delivery rate, package type, stock reservation, inventory mutation, physical fulfillment or subscription path.

## 12. External operational blockers before production

- Confirm PayPal capture-at-checkout configuration and production webhook registration.
- Confirm PayPal Payouts API eligibility only if automation is later required; manual payouts remain the first-release design.
- Select malware scanning and media processing services and configure private storage.
- Approve creator identity/age/rights/consent verification policy and reviewer procedures.
- Define dispute/chargeback response operations and manual PayPal case hold process.
- Set the exact hold duration and minimum payout amount.
- Complete legal, privacy, data retention and consumer-rights review for the marketplace's operating jurisdictions.


## Implementation progress — M1 financial release foundation

Implemented on `feat/digital-only-marketplace`:

- Added nullable `creator_earnings_hold_days` store preference. No duration is assumed: when unset, new earnings are recorded but remain ineligible for payout (fail-closed).
- Added `release_at` to seller transfers. New earnings derive it from the order fulfillment timestamp plus the configured number of days.
- Existing transfers are backfilled to their original `created_at`, preserving their pre-existing payout eligibility.
- Added `Spree::SellerTransferHold` as a store-scoped, auditable record with independent hold kinds (`refund_review`, `dispute`, `manual_review`, `compliance`), active/released status, reason, optional source reference, metadata, creator/releaser admin references and release timestamp.
- Added a release operation that requires an administrator and preserves the release note and audit fields.
- Updated payout selection to exclude earnings whose release time has not arrived or which have any active hold. Refund reversals follow the original earning's release/hold eligibility.
- Added model/workflow specs and factories for release times and financial holds.

Validation limitation: these changes were committed through the GitHub repository API. The repository test suite has not been executed in a local checkout, so the added specs are not yet reported as passing. Before deployment, run the core model and workflow specs through the repository's prescribed `scripts/test/` runner.


## Implementation progress — digital media versioning and moderation history

Added to the feature branch:

- `Spree::DigitalAssetVersion`: one immutable revision record per upload, with store, version number, private Active Storage attachment, checksum, MIME type, byte size, submission timestamp and pending/approved/rejected status.
- `Spree::DigitalAssetModeration`: a moderation trail tied to the exact asset revision, with reviewer, decision, reason code, notes, timestamp and metadata. Decisions are append-only; corrections or later approval must be new records rather than rewriting history.
- Digital asset create/update workflows now preserve each uploaded blob as a separately attached private version before a later replacement can overwrite the current delivery attachment.
- Each new upload creates a pending moderation record and pending version. Replacing a file therefore does not erase the earlier blob or transfer its moderation decision to the replacement.
- Added workflow/model specs covering first upload, replacement, historical blob preservation, pending moderation and append-only decisions.

Important remaining integration work: the storefront delivery and download authorization paths have not yet been changed to require an approved moderation decision for the exact current version. Until that gate is implemented and tested end-to-end, this work is a persistence/audit foundation, not a completed moderation enforcement system. Existing download delivery behaviour remains unchanged at this checkpoint.

Validation limitation: specs have been added but have not been run in a local checkout. Use the repository's prescribed `scripts/test/` runner before deployment.


### Delivery enforcement added after the versioning checkpoint

- `Spree::DigitalAsset#approved_for_delivery?` now fails closed unless the current private attachment matches the latest preserved version, that version is marked approved, and an explicit approved moderation decision exists for that exact version.
- The v3 digital-link download endpoint now checks this predicate before generating a delivery URL or consuming a download click.
- Legacy assets without version history, newly uploaded pending assets, and replaced assets awaiting review cannot be downloaded through this endpoint.
- The moderator-facing approval workflow and storefront catalog/search visibility filter are still outstanding. This endpoint gate is not a substitute for those remaining controls.


### Moderator decision workflow added

- Added `Spree::DigitalAssets::Moderate` to approve or reject one pending uploaded revision.
- The operation requires an administrator, locks the version, rechecks that it is still the current delivery revision, updates its status transactionally and appends a separate moderation decision with reviewer, timestamp, reason code and notes.
- Stale revisions cannot be approved after a replacement upload. Repeated decisions are refused because the version must still be pending.
- Added workflow specs for approval, rejection, missing reviewer and stale-version rejection.
- The workflow is the domain operation only; an authenticated admin API endpoint and dashboard moderation queue still need to be connected.


### Storefront and cart eligibility enforcement added

- Added `Product.digital_marketplace_visible` as a relation-level eligibility predicate. It requires a sellable (approved and not on holiday) seller wherever seller ownership is assigned, at least one digital asset, and an explicitly approved moderation decision for the latest version of every asset.
- The catalog predicate also checks that the approved version's private Active Storage blob is still the exact blob attached as the asset's current delivery file. A stale approval cannot keep a replaced file visible.
- Applied the predicate after buyer catalog/context resolution in the v3 storefront product scope. Product index, direct ID/slug lookup, search-provider product results and the filters endpoint therefore inherit the same eligible relation.
- Applied the same predicate to `SalesContext#orderable_variants`, which is the common variant eligibility path used by carts and checkout. An ineligible creator listing cannot be added to a cart through the normal sales-context path.
- Remaining validation work: add focused database/request specs for mixed seller ownership, pending/rejected/latest-version media, replacement blobs, search and facets; inspect every alternate admin/draft-order path; and execute the prescribed test suite. These changes have not yet been run locally.


### Visibility predicate hardening and regression coverage

- Corrected the latest-version subquery to compare version primary keys (rather than accidentally comparing version IDs to asset IDs).
- The catalog predicate now also requires the approved revision's Active Storage blob to match the asset's current attachment at query time.
- Corrected the version/store consistency validation to resolve the store through `DigitalAsset#store`; DigitalAsset does not own a `store_id` column.
- Added focused model coverage for products without digital assets, pending media, approved current media and a replaced current blob.
- Tests remain unexecuted in a local checkout; the suite must run through `scripts/test/`.


### Admin moderation API added

- Added store-scoped `GET /api/v3/admin/digital_asset_versions` with a pending-by-default queue and optional status filter.
- Added `GET /api/v3/admin/digital_asset_versions/:id`, plus administrator `PATCH .../:id/approve` and `PATCH .../:id/reject`.
- Decisions are routed through the domain moderation workflow, require the authenticated staff user, and preserve reason code, notes, reviewer and timestamp.
- The API queries revisions by the active store rather than trusting a client-supplied store or asset ID.
- The dashboard still needs a moderation queue screen and action controls; endpoint request specs and route/policy verification remain outstanding. No local test run has been performed.


### Creator onboarding made digital-only

- The default seller checklist now contains terms acceptance, creator profile, billing address and initial listing.
- Returns address, delivery method and package type have been removed from the default checklist.
- A forward migration deactivates those three physical-fulfilment requirements on existing stores without deleting their historical submissions.
- Identity/age evidence, rights ownership and consent are intentionally represented by operator-configured Document, Attestation and OperatorReview requirements. The exact evidence and wording must be set by the marketplace before creator onboarding is opened.
- DigitalAssetVersion upload identity fields are now immutable after creation; moderation may change only its review status.
- Admin moderation authorization is delegated to existing product read/update permissions, avoiding a new unregistered permission family.


## Implementation update — mandatory creator verification

The default seller checklist now provisions required, active requirements for:
- identity document submission with human review and explicit age verification (18+);
- a legal-age declaration;
- ownership/control of the rights needed to license each submitted item;
- informed consent and authorization for every identifiable participant.

These named requirements are provisioned idempotently alongside the existing profile, terms, billing and initial-listing requirements. The marketplace must not approve a creator while any required item remains incomplete, pending or rejected. The declarations are recorded as seller requirement submissions; the identity document is private and operator-reviewed. This is an operational verification gate, not a claim that a document alone proves legal capacity or rights in every jurisdiction.

Media revision hardening: the original private attachment may be assigned when a revision is first created, but an already attached revision cannot be repointed to different bytes. Replacements must create a new version and a new moderation decision. Media rejection authorization uses the same product update permission as approval.
