# frozen_string_literal: true

module Spree
  # Append-only moderation decision for one exact uploaded file revision.
  # A later upload creates a new version and a new decision trail; it cannot
  # inherit approval from an earlier file.
  class DigitalAssetModeration < Spree.base_class
    has_prefix_id :dam

    include Spree::Metadata
    include Spree::SingleStoreResource

    DECISIONS = %w[pending approved rejected].freeze

    belongs_to :digital_asset, class_name: 'Spree::DigitalAsset', inverse_of: :moderations
    belongs_to :digital_asset_version, class_name: 'Spree::DigitalAssetVersion',
                                      inverse_of: :moderations
    belongs_to :reviewed_by_admin_user, class_name: 'Spree::AdminUser', optional: true

    before_update :prevent_decision_rewrite!
    before_destroy :prevent_decision_deletion!

    validates :decision, inclusion: { in: DECISIONS }
    validates :decided_at, presence: true, if: -> { decision.in?(%w[approved rejected]) }
    validates :reviewed_by_admin_user, presence: true, if: -> { decision.in?(%w[approved rejected]) }
    validate :version_belongs_to_same_asset_and_store

    scope :latest_first, -> { order(created_at: :desc, id: :desc) }
    scope :awaiting_review, -> { where(decision: 'pending') }

    private

    def prevent_decision_rewrite!
      raise ActiveRecord::ReadOnlyRecord, 'Moderation decisions are append-only; create a new decision instead'
    end

    def prevent_decision_deletion!
      raise ActiveRecord::ReadOnlyRecord, 'Moderation decisions are retained as an audit record'
    end

    def version_belongs_to_same_asset_and_store
      return unless digital_asset_version

      unless digital_asset_version.digital_asset_id == digital_asset_id &&
             digital_asset_version.store_id == store_id
        errors.add(:digital_asset_version, :invalid)
      end
    end
  end
end
