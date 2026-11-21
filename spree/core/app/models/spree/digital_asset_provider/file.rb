module Spree
  module DigitalAssetProvider
    # The default provider: an uploaded file on private storage. Reproduces the
    # pre-wave-6 download behaviour — a short-lived signed storage URL the
    # customer is redirected to — now expressed through the provider seam.
    class File < Base
      def self.requires_attachment?
        true
      end

      def deliver(digital_link, expires_in:)
        version = digital_link.digital_asset_version
        attachment = if version
                       return unless version.available_for_sale? && version.digital_asset_id == digital_asset.id
                       version.attachment
                     else
                       return if digital_link.store.preferred_digital_creator_marketplace_enabled && digital_asset.versions.latest_first.first&.status == 'removed'
                       digital_asset.attachment
                     end
        return unless attachment.attached?

        Spree::DigitalDelivery.new(
          redirect_url: attachment.url(expires_in: expires_in, disposition: :attachment)
        )
      end
    end
  end
end
