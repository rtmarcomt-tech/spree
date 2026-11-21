# frozen_string_literal: true

module Spree
  # An auditable reason why an otherwise earned transfer must not be paid.
  #
  # Holds are additive records rather than a mutable flag on the earning:
  # multiple independent controls (refund review, dispute, compliance) may
  # overlap, and releasing one must never release another.
  class SellerTransferHold < Spree.base_class
    has_prefix_id :vth

    include Spree::Metadata
    include Spree::SingleStoreResource
    include Spree::HasStatus

    KINDS = %w[refund_review dispute manual_review compliance].freeze

    belongs_to :seller, class_name: 'Spree::Seller'
    belongs_to :seller_transfer, class_name: 'Spree::SellerTransfer', inverse_of: :holds
    belongs_to :created_by_admin_user, class_name: 'Spree::AdminUser', optional: true
    belongs_to :released_by_admin_user, class_name: 'Spree::AdminUser', optional: true

    has_status :active, :released, default: :active

    validates :kind, inclusion: { in: KINDS }
    validates :reason, presence: true
    validates :released_at, presence: true, if: :released?
    validates :released_by_admin_user, presence: true, if: :released?
    validate :transfer_belongs_to_same_store_and_seller

    scope :blocking, -> { active }

    # Release this hold without changing or deleting its audit history.
    def release!(admin_user:, note: nil)
      raise ArgumentError, 'admin_user is required' unless admin_user

      with_lock do
        return self if released?

        update!(
          status: 'released',
          released_at: Time.current,
          released_by_admin_user: admin_user,
          metadata: metadata.merge('release_note' => note).compact
        )
      end
    end

    private

    def transfer_belongs_to_same_store_and_seller
      return unless seller_transfer

      errors.add(:seller_transfer, :invalid) unless
        seller_transfer.store_id == store_id && seller_transfer.seller_id == seller_id
    end
  end
end
