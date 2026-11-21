# Pin each digital entitlement to the exact published upload it represents.
class PinDigitalLinksToAssetVersions < ActiveRecord::Migration[8.1]
  def up
    add_reference :spree_digital_links, :digital_asset_version,
                  foreign_key: { to_table: :spree_digital_asset_versions },
                  index: true,
                  null: true

    # Existing Spree assets predate immutable revisions. Preserve their
    # current private blob as revision 1 before requiring version-pinned
    # delivery in creator-marketplace mode.
    Spree::DigitalAsset.find_each do |asset|
      next unless asset.attachment.attached?

      version = asset.versions.latest_first.first
      unless version
        blob = asset.attachment.blob
        version = asset.versions.build(
          store: asset.store,
          version_number: 1,
          checksum: blob.checksum,
          content_type: blob.content_type,
          byte_size: blob.byte_size,
          status: 'published',
          submitted_at: Time.current
        )
        version.attachment.attach(blob)
        version.save!
      end

      asset.digital_links.where(digital_asset_version_id: nil).
        update_all(digital_asset_version_id: version.id)
    end
  end

  def down
    remove_reference :spree_digital_links, :digital_asset_version,
                     foreign_key: { to_table: :spree_digital_asset_versions },
                     index: true
  end
end
