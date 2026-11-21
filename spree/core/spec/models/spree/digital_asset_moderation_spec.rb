require 'spec_helper'

RSpec.describe Spree::DigitalAssetModeration, type: :model do
  let(:digital_asset) { create(:digital_asset) }
  let(:store) { digital_asset.store }
  let(:version) do
    blob = digital_asset.attachment.blob
    Spree::DigitalAssetVersion.new(
      store: store,
      digital_asset: digital_asset,
      version_number: 1,
      checksum: blob.checksum,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      status: 'published',
      submitted_at: Time.current
    ).tap { |item| item.attachment.attach(blob); item.save! }
  end

  it 'allows creator uploads to be immediately available without an admin decision' do
    expect(version).to be_available_for_sale
    expect(digital_asset.reload).to be_approved_for_delivery
  end

  it 'does not permit replacing the bytes attached to an existing revision' do
    replacement = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new('replacement bytes'),
      filename: 'replacement.pdf',
      content_type: 'application/pdf',
      service_name: Spree.private_storage_service_name
    )

    expect { version.attachment.attach(replacement) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'records an administrator removal as an immutable audit entry' do
    moderation = described_class.create!(
      store: store,
      digital_asset: digital_asset,
      digital_asset_version: version,
      decision: 'removed',
      reviewed_by_admin_user: create(:admin_user),
      reason_code: 'policy_violation',
      decided_at: Time.current
    )

    expect(moderation).to be_persisted
    expect { moderation.update!(notes: 'rewritten') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { moderation.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
