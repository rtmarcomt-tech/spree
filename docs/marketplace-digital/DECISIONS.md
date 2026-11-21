# Decision log

## 2026-11-21 — Marketplace foundation study

- Selected direction: use a proven commerce framework and implement marketplace-specific business logic in first-party modules.
- Bagisto is the current preferred candidate because it is Laravel-based and exposes a documented PayPal integration and downloadable products. The Bagisto 2.5 branch declares Laravel 13, PHP 8.4 and MIT licensing in composer.json/LICENSE.
- Bagisto's multi-vendor marketplace is documented as a separate extension; the core repository tree inspected for branch 2.5 did not contain marketplace/seller packages. Do not assume those capabilities are included in the core or license them into the build without further verification.
- Spree is present in the user's GitHub account but is a Ruby on Rails commerce platform. Its documented seller payout ledger relies on Stripe Connect. It is not selected as the base for this build because the user's payment decision is PayPal-only.
- PayPal checkout and seller payouts are separate capabilities. Payout API availability, country eligibility, account approval, KYC requirements, fees, timing and limits must be verified against the actual platform PayPal account before promising automated creator payouts.
- No Stripe integration is to be introduced unless the user explicitly changes this decision.
- No physical products, stock, shipping, bundles or subscriptions in the initial scope.
- No pre-publication editorial moderation in the initial scope. Seller verification before selling remains mandatory.

## Open technical gates

1. Verify latest supported Bagisto release and PHP/runtime requirements before pinning versions.
2. Inspect actual PayPal module implementation, webhook verification and refund support.
3. Verify downloadable product implementation and adapt it for private original media with one-time purchase entitlements.
4. Obtain the official multi-vendor extension's source/license/technical terms if considering reuse; otherwise implement own vendor domain modules.
5. Confirm creator payouts on the platform's PayPal Business account and choose automated vs audited manual payout flow.
6. Define legal/tax treatment of marketplace commission, creator proceeds and required seller verification for target territories.
