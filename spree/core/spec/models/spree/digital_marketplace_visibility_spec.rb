require 'spec_helper'

RSpec.describe Spree::Product, type: :model do
  describe '.digital_marketplace_visible' do
    let(:product) { create(:product) }
    let(:asset) { create(:digital_asset, variant: product.default_variant) }
    let(:blob) { asset.attachment.blob }
    let!(:version) do
      Spree::DigitalAssetVersion.new(
        store: product.store,
        digital_asset: asset,
        version_number: 1,
        checksum: blob.checksum,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        status: 'published',
        submitted_at: Time.current
      ).tap { |record| record.attachment.attach(blob); record.save! }
    end


    it 'excludes products without a digital asset' do
      ordinary_product = create(:product)

      expect(described_class.digital_marketplace_visible).not_to include(ordinary_product)
    end

    it 'includes a creator product immediately after its media is published' do
      expect(described_class.digital_marketplace_visible).to include(product)
    end

    it 'excludes a product after an administrator removes its current media version' do
      version.update!(status: 'removed')

      expect(described_class.digital_marketplace_visible).not_to include(product)
    end

  end
end
