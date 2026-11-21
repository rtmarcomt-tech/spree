# Adds explicit release eligibility and auditable financial holds to seller earnings.
#
# Existing ledger rows predate configurable holds. Backfilling their creation
# time preserves the payout eligibility they already had; only new earnings
# are subject to the newly configured hold period.
class AddCreatorEarningsReleaseControls < ActiveRecord::Migration[8.1]
  def change
    add_column :spree_seller_transfers, :release_at, :datetime
    add_index :spree_seller_transfers, [:seller_id, :release_at],
              name: 'index_seller_transfers_on_seller_and_release_at'

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE spree_seller_transfers
          SET release_at = created_at
          WHERE release_at IS NULL
        SQL
      end
    end

    create_table :spree_seller_transfer_holds do |t|
      t.references :store, null: false
      t.references :seller, null: false
      t.references :seller_transfer, null: false
      t.references :created_by_admin_user, null: true
      t.references :released_by_admin_user, null: true

      t.string :kind, null: false
      t.string :status, null: false
      t.string :source_reference
      t.text :reason
      t.datetime :released_at
      if t.respond_to?(:jsonb)
        t.jsonb :metadata
      else
        t.json :metadata
      end
      t.timestamps
    end

    add_index :spree_seller_transfer_holds, [:seller_transfer_id, :status],
              name: 'index_seller_transfer_holds_on_transfer_and_status'
    add_index :spree_seller_transfer_holds, [:store_id, :kind, :status],
              name: 'index_seller_transfer_holds_on_store_kind_status'
  end
end
