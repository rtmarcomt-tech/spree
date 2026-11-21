module Spree
  module Api
    module V3
      module Admin
        # Operator review of uploaded creator deliverables. Every decision is
        # made against one store-scoped, immutable upload revision.
        class DigitalAssetVersionsController < ResourceController
          before_action :set_resource, only: [:show, :preview, :approve, :reject]

          request_params 'DigitalAssetVersionDecisionParams', action: :approve do |body|
            body.attribute :reason_code, :string
            body.attribute :notes, :string
          end

          request_params 'DigitalAssetVersionDecisionParams', action: :reject do |body|
            body.attribute :reason_code, :string, required: true
            body.attribute :notes, :string
          end

          # GET /api/v3/admin/digital_asset_versions?status=pending
          # The queue is store-scoped and defaults to pending reviews.
          def index
            authorize! :read, Spree::Product

            status = params[:status].presence || 'pending'
            unless Spree::DigitalAssetVersion::STATUSES.include?(status)
              return render_error(
                code: ERROR_CODES[:validation_error],
                message: 'Unsupported digital asset version status',
                status: :unprocessable_entity
              )
            end

            versions = Spree::DigitalAssetVersion.where(store_id: current_store.id).
              includes(:digital_asset, :moderations).
              where(status: status).
              order(submitted_at: :asc)

            render json: {
              data: versions.map do |version|
                {
                  id: version.prefixed_id,
                  digital_asset_id: version.digital_asset.prefixed_id,
                  product_id: version.digital_asset.product.prefixed_id,
                  product_title: version.digital_asset.product.name,
                  seller_id: version.digital_asset.product.seller&.prefixed_id,
                  seller_name: version.digital_asset.product.seller&.name,
                  file_name: version.attachment.filename.to_s,
                  preview_url: "/api/v3/admin/digital_asset_versions/#{version.prefixed_id}/preview",
                  version_number: version.version_number,
                  status: version.status,
                  content_type: version.content_type,
                  byte_size: version.byte_size,
                  submitted_at: version.submitted_at,
                  moderation_history: version.moderations.latest_first.map do |decision|
                    {
                      decision: decision.decision,
                      reason_code: decision.reason_code,
                      notes: decision.notes,
                      decided_at: decision.decided_at,
                      reviewer_id: decision.reviewed_by_admin_user&.prefixed_id
                    }
                  end
                }
              end
            }
          end

          def show
            authorize! :read, @resource.digital_asset.product
            render_version
          end

          # Streams the exact private revision to an authenticated operator.
          # No Active Storage public URL or long-lived signed URL is exposed.
          def preview
            authorize! :read, @resource.digital_asset.product

            return head :not_found unless @resource.attachment.attached?

            response.headers['X-Content-Type-Options'] = 'nosniff'
            response.headers['Content-Security-Policy'] = "default-src 'none'; sandbox"
            send_data @resource.attachment.download,
                      type: @resource.content_type,
                      disposition: 'inline',
                      filename: @resource.attachment.filename.to_s
          end

          def approve
            authorize! :update, @resource.digital_asset.product
            decide('approved')
          end

          def reject
            authorize! :update, @resource.digital_asset.product
            decide('rejected')
          end

          private

          def set_resource
            @resource = Spree::DigitalAssetVersion.where(store_id: current_store.id).find_by_param!(params[:id])
          end

          def decide(decision)
            result = Spree::DigitalAssets::Moderate.call(
              digital_asset_version: @resource,
              decision: decision,
              reviewer: try_spree_current_user,
              reason_code: params[:reason_code],
              notes: params[:notes]
            )

            return render_service_error(result.error) unless result.success?

            @resource.reload
            render_version
          end

          def render_version
            render json: {
              data: {
                id: @resource.prefixed_id,
                digital_asset_id: @resource.digital_asset.prefixed_id,
                version_number: @resource.version_number,
                status: @resource.status,
                submitted_at: @resource.submitted_at
              }
            }
          end
        end
      end
    end
  end
end
