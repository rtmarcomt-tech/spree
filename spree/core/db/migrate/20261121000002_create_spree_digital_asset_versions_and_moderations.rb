# Preserve every uploaded digital-asset revision independently of the
# mutable delivery attachment on Spree::DigitalAsset.
class CreateSpreeDigitalAssetVersionsAndModerations < ActiveRecord::Migration[8.1]
  def change
    create_table :spree_digital_asset_versions do |t|
      t.references :store, null: false
      t.references :digital_asset, null: false
      t.integer :version_number, null: false
      t.string :checksum, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :status, null: false
      t.datetime :submitted_at, null: false
      t.timestamps
    end
    add_index :spree_digital_asset_versions, [:digital_asset_id, :version_number],
              unique: true, name: 'index_digital_asset_versions_on_asset_and_number'
    add_index :spree_digital_asset_versions, [:store_id, :status, :submitted_at],
              name: 'index_digital_asset_versions_on_store_status'

    create_table :spree_digital_asset_moderations do |t|
      t.references :store, null: false
      t.references :digital_asset, null: false
      t.references :digital_asset_version, null: false
      t.references :reviewed_by_admin_user, null: true
      t.string :decision, null: false
      t.string :reason_code
      t.text :notes
      t.datetime :decided_at
      if t.respond_to?(:jsonb)
        t.jsonb :metadata
      else
        t.json :metadata
      end
      t.timestamps
    end
    add_index :spree_digital_asset_moderations, [:digital_asset_version_id, :created_at],
              name: 'index_digital_asset_moderations_on_version_and_date'
    add_index :spree_digital_asset_moderations, [:store_id, :decision, :created_at],
              name: 'index_digital_asset_moderations_on_store_decision'
  end
end
