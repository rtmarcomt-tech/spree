module Spree
  class DigitalLink < Spree.base_class
    has_prefix_id :dl  # Spree-specific: digital link

    publishes_lifecycle_events
    publishes_event :downloaded

    has_secure_token on: :save

    if defined?(Spree::Security::DigitalLinks)
      include Spree::Security::DigitalLinks
    end

    belongs_to :digital_asset, class_name: 'Spree::DigitalAsset'
    belongs_to :digital_asset_version, class_name: 'Spree::DigitalAssetVersion', optional: true
    belongs_to :line_item, class_name: 'Spree::LineItem'

    validate :pinned_version_matches_asset

    before_validation :set_defaults, on: :create
    validates :access_counter, numericality: { greater_than_or_equal_to: 0 }

    # Existing purchases retain their pinned revision unless an administrator removes it.
    def filename
      digital_asset_version&.attachment&.filename || digital_asset.filename
    end

    def content_type
      digital_asset_version&.content_type || digital_asset.content_type
    end

    def deliverable_version?
      if store.preferred_digital_creator_marketplace_enabled
        digital_asset_version&.available_for_sale? && digital_asset_version.digital_asset_id == digital_asset_id
      else
        digital_asset_version.nil? || (digital_asset_version.available_for_sale? && digital_asset_version.digital_asset_id == digital_asset_id)
      end
    end
    # The order's store is authoritative for both the download-limit flags and,
    # passed into the asset, the limit values — so one store answers the whole
    # check. Public so the keyless download endpoint can derive store context
    # from the link (emailed links carry no publishable key).
    delegate :store, to: :line_item
    delegate :order, to: :line_item

    # @deprecated Use {#digital_asset}; removed in 6.3.
    def digital
      Spree::Deprecation.warn('Spree::DigitalLink#digital is deprecated and will be removed in Spree 6.3. Use #digital_asset instead.')
      digital_asset
    end

    # @deprecated Use {#digital_asset=}; removed in 6.3.
    def digital=(value)
      Spree::Deprecation.warn('Spree::DigitalLink#digital= is deprecated and will be removed in Spree 6.3. Use #digital_asset= instead.')
      self.digital_asset = value
    end

    def authorizable?
      deliverable_version? && !(expired? || access_limit_exceeded?)
    end

    def expired?
      expiry = expires_at
      expiry.present? && expiry <= Time.current
    end

    def access_limit_exceeded?
      if store.preferred_limit_digital_download_count
        access_counter >= digital_asset.effective_authorized_clicks(store)
      else
        false
      end
    end

    # This method should be called when a download is initiated.
    # It returns +true+ or +false+ depending on whether the authorization is granted.
    #
    # The access-limit check and the counter increment run inside a row lock so
    # concurrent requests sharing the same token cannot each pass the cap before
    # any of them increments the counter (TOCTOU race).
    def authorize!
      ActiveRecord::Base.connected_to(role: :writing) do
        with_lock do
          authorizable? && increment!(:access_counter, touch: true)
        end
      end
    end

    def reset!
      self.access_counter = 0
      self.created_at = Time.current
      save!
    end

    # @return [Time, nil] when access lapses, or nil when day limits are off
    def expires_at
      return unless store.preferred_limit_digital_download_days

      created_at + digital_asset.effective_authorized_days(store).days
    end

    private

    def set_defaults
      self.access_counter ||= 0
    end

    def pinned_version_matches_asset
      return if digital_asset_version.nil? || digital_asset.nil?
      return if digital_asset_version.digital_asset_id == digital_asset_id && digital_asset_version.store_id == store.id

      errors.add(:digital_asset_version, :invalid)
    end
  end
end
