# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'Admin Digital Asset Versions API', type: :request, swagger_doc: 'api-reference/admin.yaml' do
  include_context 'API v3 Admin'

  let(:Authorization) { "Bearer #{admin_jwt_token}" }
  let!(:product) { create(:product, store: store) }
  let!(:digital_asset) { create(:digital_asset, variant: product.default_variant) }
  let!(:version) do
    blob = digital_asset.attachment.blob
    Spree::DigitalAssetVersion.create!(
      store: store,
      digital_asset: digital_asset,
      version_number: 1,
      checksum: blob.checksum,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      status: 'published',
      submitted_at: Time.current
    ).tap { |record| record.attachment.attach(blob) }
  end

  path '/api/v3/admin/digital_asset_versions/{id}/remove' do
    parameter name: :id, in: :path, type: :string, required: true, description: 'Digital asset version prefixed ID'

    patch 'Remove a published creator file' do
      tags 'Digital asset versions'
      consumes 'application/json'
      produces 'application/json'
      security [api_key: [], bearer_auth: []]
      description 'Removes a published creator file from sale after an administrator identifies a policy violation. Creator uploads are published immediately and are not pre-approved.'
      admin_scope :write, :products

      parameter name: 'x-spree-api-key', in: :header, type: :string, required: true
      parameter name: :Authorization, in: :header, type: :string, required: true
      request_body_for(reason_code: 'policy_violation', notes: 'Violates marketplace rules')

      let(:'x-spree-api-key') { secret_api_key.plaintext_token }
      let(:id) { version.prefixed_id }
      let(:body) { { reason_code: 'policy_violation', notes: 'Violates marketplace rules' } }

      response '200', 'publication removed' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              id: { type: :string },
              digital_asset_id: { type: :string },
              version_number: { type: :integer },
              status: { type: :string },
              submitted_at: { type: :string, format: 'date-time' }
            },
            required: %w[id digital_asset_id version_number status submitted_at]
          }
        }

        run_test! do |response|
          expect(JSON.parse(response.body).dig('data', 'status')).to eq('removed')
          expect(version.reload).not_to be_available_for_sale
        end
      end
    end
  end
end
