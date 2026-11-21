require 'spec_helper'

RSpec.describe Spree::Product, type: :model do
  describe '.digital_marketplace_visible' do
    let(:product) { create(:product) }
    let(:asset) { create(:digital_asset, variant: product.default_variant) }
    let(:blob) { asset.attachment.blob }
    let!(:version) do
      Spree::DigitalAssetVersion.create!(
        store: product.store,
        digital_asset: asset,
        version_number: 1,
        checksum: blob.checksum,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        status: 'pending',
        submitted_at: Time.current
      ).tap { |record| record.attachment.attach(blob) }
    end

    before do
      asset.moderations.create!(
        store: product.store,
        digital_asset_version: version,
        decision: 'pending'
      )
    end

    it 'excludes products without a digital asset' do
      ordinary_product = create(:product)

      expect(described_class.digital_marketplace_visible).not_to include(ordinary_product)
    end

    it 'excludes a product while its current media version is pending' do
      expect(described_class.digital_marketplace_visible).not_to include(product)
    end

    it 'includes the product only after the current media version is approved' do
      result = Spree::DigitalAssets::Moderate.call(
        digital_asset_version: version,
        decision: 'approved',
        reviewer: create(:admin_user)
      )

      expect(result).to be_success
      expect(described_class.digital_marketplace_visible).to include(product)
    end

    it 'excludes the product when the approved version is no longer the current blob' do
      result = Spree::DigitalAssets::Moderate.call(
        digital_asset_version: version,
        decision: 'approved',
        reviewer: create(:admin_user)
      )
      expect(result).to be_success

      replacement = ActiveStorage::Blob.create_and_upload!(
        io: File.open(Spree::Core::Engine.root.join('spec', 'fixtures', 'thinking-cat.jpg')),
        filename: 'replacement.jpg',
        content_type: 'image/jpeg',
        service_name: Spree.private_storage_service_name
      )
      asset.attachment.attach(replacement)

      expect(described_class.digital_marketplace_visible).not_to include(product)
    end
  end
end
