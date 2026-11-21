FactoryBot.define do
  factory :seller_transfer, class: Spree::SellerTransfer do
    seller
    store { seller.store }
    order
    amount { BigDecimal(20) }
    currency { 'USD' }
    kind { 'earning' }
    provider { Spree::PayoutProvider::System.provider_key }
    status { 'pending' }
    # Historical specs model transfers that are already past any hold period.
    release_at { Time.current }

    trait :completed do
      status { 'completed' }
    end

    trait :reversal do
      kind { 'refund_reversal' }
      amount { BigDecimal(-5) }
    end
  end
end
