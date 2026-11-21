require 'spec_helper'

RSpec.describe Spree::DigitalAssetModeration, type: :model do
  let(:digital_asset) { create(:digital_asset) }
  let(:store) { digital_asset.store }
  let(:version) do
    blob = digital_asset.attachment.blob
    record = described_class::DigitalAssetVersion rescue nil
    Spree::DigitalAssetVersion.create!(
      store: store,
      digital_asset: digital_asset,
      version_number: 1,
      checksum: blob.checksum,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      status: 'pending',
      submitted_at: Time.current
    ).tap { |item| item.attachment.attach(blob) }
  end

  it 'requires the moderation decision to refer to the same asset version' do
    moderation = described_class.new(
      store: store,
      digital_asset: digital_asset,
      digital_asset_version: version,
      decision: 'pending'
    )

    expect(moderation).to be_valid
  end

  it 'does not permit rewriting a recorded decision' do
    moderation = described_class.create!(
      store: store,
      digital_asset: digital_asset,
      digital_asset_version: version,
      decision: 'pending'
    )

    expect { moderation.update!(decision: 'approved') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'does not permit deleting a recorded decision' do
    moderation = described_class.create!(
      store: store,
      digital_asset: digital_asset,
      digital_asset_version: version,
      decision: 'pending'
    )

    expect { moderation.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
