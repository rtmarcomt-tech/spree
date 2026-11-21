# Pin each digital entitlement to the exact approved upload that was sold.
class PinDigitalLinksToAssetVersions < ActiveRecord::Migration[8.1]
  def change
    add_reference :spree_digital_links, :digital_asset_version,
                  foreign_key: { to_table: :spree_digital_asset_versions },
                  index: true,
                  null: true
  end
end
