# frozen_string_literal: true

# This deployment is a digital-only creator marketplace. Shipping, returns
# addresses and package configuration are not onboarding requirements here.
class DisablePhysicalSellerOnboardingRequirements < ActiveRecord::Migration[8.1]
  PHYSICAL_REQUIREMENTS = %w[
    Spree::SellerRequirements::ReturnsAddress
    Spree::SellerRequirements::DeliveryMethod
    Spree::SellerRequirements::PackageType
  ].freeze

  def up
    return unless table_exists?(:spree_seller_requirements)

    execute <<~SQL
      UPDATE spree_seller_requirements
      SET active = #{connection.adapter_name.downcase.include?('postgres') ? 'FALSE' : '0'}
      WHERE type IN (#{PHYSICAL_REQUIREMENTS.map { |type| connection.quote(type) }.join(', ')})
    SQL

    # Also guard stores provisioned after the one-off migration has run. The
    # onboarding evaluator treats inactive rows as absent, regardless of their
    # required flag, preserving audit/history while removing physical steps.
    store_ids = select_values('SELECT id FROM spree_stores')
    store_ids.each do |store_id|
      execute <<~SQL
        UPDATE spree_seller_requirements
        SET active = #{connection.adapter_name.downcase.include?('postgres') ? 'FALSE' : '0'}
        WHERE store_id = #{connection.quote(store_id)}
          AND type IN (#{PHYSICAL_REQUIREMENTS.map { |type| connection.quote(type) }.join(', ')})
      SQL
    end
  end

  def down
    # Do not reactivate physical requirements automatically; an operator may
    # have deliberately changed the store checklist since this migration ran.
  end
end
