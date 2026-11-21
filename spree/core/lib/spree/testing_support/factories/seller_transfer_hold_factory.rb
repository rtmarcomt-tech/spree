FactoryBot.define do
  factory :seller_transfer_hold, class: Spree::SellerTransferHold do
    seller_transfer
    seller { seller_transfer.seller }
    store { seller_transfer.store }
    kind { 'manual_review' }
    status { 'active' }
    reason { 'Administrative review' }
  end
end
