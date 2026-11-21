# frozen_string_literal: true

module Spree
  module DigitalAssets
    # Records an operator's decision against one immutable uploaded revision.
    # The pending submission remains in the audit trail; a decision is a new row.
    class Moderate < Spree::Workflow
      def perform(digital_asset_version:, decision:, reviewer:, reason_code: nil, notes: nil)
        super

        reject!(:invalid_decision) unless %w[approved rejected].include?(decision.to_s)
        reject!(:reviewer_required) if reviewer.nil?
        reject!(:version_not_pending) unless digital_asset_version.status == 'pending'
        reject!(:version_not_current) unless current_version?

        # Uploads serialize version creation against the asset row. Moderation
        # must take that same lock before locking the version; otherwise a new
        # upload can replace the current attachment while an older revision is
        # being approved.
        ApplicationRecord.transaction do
          asset = digital_asset_version.digital_asset

          asset.with_lock do
            digital_asset_version.with_lock do
              reject!(:version_not_pending) unless digital_asset_version.status == 'pending'
              reject!(:version_not_current) unless current_version?

              digital_asset_version.update!(status: decision.to_s)
              asset.moderations.create!(
                store: digital_asset_version.store,
                digital_asset_version: digital_asset_version,
                decision: decision.to_s,
                reviewed_by_admin_user: reviewer,
                reason_code: reason_code,
                notes: notes,
                decided_at: Time.current
              )
            end
          end
        end

        digital_asset_version.digital_asset.publish_event("digital_asset.#{decision}")
        success(digital_asset_version)
      end

      private

      def current_version?
        asset = digital_asset_version.digital_asset
        asset.versions.latest_first.first == digital_asset_version &&
          asset.attachment.attached? &&
          digital_asset_version.attachment.attached? &&
          asset.attachment.blob_id == digital_asset_version.attachment.blob_id
      end
    end
  end
end
