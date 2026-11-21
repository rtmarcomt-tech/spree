require 'spec_helper'

RSpec.describe Spree::DigitalAssets::Moderate do
  let(:digital_asset) { create(:digital_asset) }
  let(:store) { digital_asset.store }
  let(:reviewer) { create(:admin_user) }
  let(:version) do
    blob = digital_asset.attachment.blob
    Spree::DigitalAssetVersion.new(
      store: store,
      digital_asset: digital_asset,
      version_number: 1,
      checksum: blob.checksum,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      status: 'pending',
      submitted_at: Time.current
    ).tap { |item| item.attachment.attach(blob); item.save! }
  end

  before do
    digital_asset.moderations.create!(
      store: store,
      digital_asset_version: version,
      decision: 'pending'
    )
  end

  it 'approves the exact current version and appends an auditable decision' do
    result = described_class.call(
      digital_asset_version: version,
      decision: 'approved',
      reviewer: reviewer,
      reason_code: 'policy_passed',
      notes: 'Reviewed manually'
    )

    expect(result).to be_success
    expect(version.reload.status).to eq('approved')
    expect(digital_asset.reload).to be_approved_for_delivery
    expect(digital_asset.moderations.order(:id).last).to have_attributes(
      decision: 'approved',
      reason_code: 'policy_passed',
      notes: 'Reviewed manually',
      reviewed_by_admin_user: reviewer
    )
  end

  it 'rejects the current version and keeps delivery blocked' do
    result = described_class.call(
      digital_asset_version: version,
      decision: 'rejected',
      reviewer: reviewer,
      reason_code: 'rights_unclear'
    )

    expect(result).to be_success
    expect(version.reload.status).to eq('rejected')
    expect(digital_asset.reload).not_to be_approved_for_delivery
  end

  it 'does not allow approval without an administrator' do
    result = described_class.call(
      digital_asset_version: version,
      decision: 'approved',
      reviewer: nil
    )

    expect(result).to be_failure
    expect(version.reload.status).to eq('pending')
  end

  it 'does not allow a stale version to be approved after a replacement upload' do
    newer = version.dup
    newer.version_number = 2
    newer.attachment.attach(version.attachment.blob)
    newer.save!

    result = described_class.call(
      digital_asset_version: version,
      decision: 'approved',
      reviewer: reviewer
    )

    expect(result).to be_failure
    expect(version.reload.status).to eq('pending')
  end
end
