# frozen_string_literal: true

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
      SET active = #{quoted_false}
      WHERE type IN (#{PHYSICAL_REQUIREMENTS.map { |type| connection.quote(type) }.join(', ')})
    SQL
  end

  def down
    # Do not reactivate physical requirements automatically: a marketplace
    # may have intentionally changed its checklist after this migration.
  end

  private

  def quoted_false
    connection.adapter_name.downcase.include?('postgres') ? 'FALSE' : '0'
  end
end
