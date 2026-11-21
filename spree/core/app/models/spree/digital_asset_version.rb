# frozen_string_literal: true

module Spree
  # Immutable uploaded revision. Delivery continues to use DigitalAsset's
  # current attachment, while this record retains the exact blob originally
  # submitted and the moderation state for that revision.
  class DigitalAssetVersion < Spree.base_class
    has_prefix_id :dav

    include Spree::SingleStoreResource

    belongs_to :digital_asset, class_name: 'Spree::DigitalAsset', inverse_of: :versions
    has_one_attached :attachment, service: Spree.private_storage_service_name
    has_many :moderations, class_name: 'Spree::DigitalAssetModeration',
                          dependent: :restrict_with_error, inverse_of: :digital_asset_version

    STATUSES = %w[pending approved rejected].freeze

    validates :version_number, numericality: { only_integer: true, greater_than: 0 }
    validates :checksum, :content_type, presence: true
    validates :byte_size, numericality: { only_integer: true, greater_than: 0 }
    validates :status, inclusion: { in: STATUSES }
    validates :submitted_at, presence: true
    validates :attachment, attached: true
    validate :asset_belongs_to_same_store

    scope :pending_review, -> { where(status: 'pending') }
    scope :latest_first, -> { order(version_number: :desc) }

    private

    def asset_belongs_to_same_store
      return unless digital_asset

      errors.add(:digital_asset, :invalid) unless digital_asset.store&.id == store_id
    end
  end
end
