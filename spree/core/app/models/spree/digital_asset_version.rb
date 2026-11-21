# frozen_string_literal: true

module Spree
  # Immutable uploaded revision. Digital links pin this record so later uploads
  # cannot change the bytes an existing buyer is entitled to receive.
  class DigitalAssetVersion < Spree.base_class
    has_prefix_id :dav

    include Spree::SingleStoreResource

    belongs_to :digital_asset, class_name: 'Spree::DigitalAsset', inverse_of: :versions
    has_one_attached :attachment, service: Spree.private_storage_service_name
    has_many :moderations, class_name: 'Spree::DigitalAssetModeration',
                          dependent: :restrict_with_error, inverse_of: :digital_asset_version

    STATUSES = %w[pending approved rejected].freeze

    IMMUTABLE_ATTRIBUTES = %w[digital_asset_id store_id version_number checksum content_type byte_size submitted_at].freeze

    before_update :prevent_upload_identity_changes!
    before_update :prevent_replacing_uploaded_attachment!

    validates :version_number, numericality: { only_integer: true, greater_than: 0 }
    validates :checksum, :content_type, presence: true
    validates :byte_size, numericality: { only_integer: true, greater_than: 0 }
    validates :status, inclusion: { in: STATUSES }
    validates :submitted_at, presence: true
    validates :attachment, attached: true
    validate :asset_belongs_to_same_store

    scope :pending_review, -> { where(status: 'pending') }
    scope :latest_first, -> { order(version_number: :desc) }

    # Approval belongs to this immutable upload, not to the asset's latest file.
    def approved?
      status == 'approved' && moderations.where(decision: 'approved').exists?
    end

    private

    def prevent_upload_identity_changes!
      changed = IMMUTABLE_ATTRIBUTES.select { |attribute| will_save_change_to_attribute?(attribute) }
      return if changed.empty?

      raise ActiveRecord::ReadOnlyRecord, "Uploaded revision identity is immutable: #{changed.join(', ')}"
    end

    # A revision may receive its original private blob after its row is
    # created, but an existing revision must never be repointed at new bytes.
    # A replacement is a new DigitalAssetVersion and therefore a new review.
    def prevent_replacing_uploaded_attachment!
      return unless attachment_changes.key?('attachment')
      # Active Storage persists the first attachment in a separate save after
      # the version row is created. Permit that initial attach, but refuse any
      # later reassignment or purge once an attachment row already exists.
      return unless attachment_attachment.present?

      raise ActiveRecord::ReadOnlyRecord, 'Uploaded revision attachment is immutable'
    end

    def asset_belongs_to_same_store
      return unless digital_asset

      errors.add(:digital_asset, :invalid) unless digital_asset.store&.id == store_id
    end
  end
end
