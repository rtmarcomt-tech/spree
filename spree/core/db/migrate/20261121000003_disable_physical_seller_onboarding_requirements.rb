# frozen_string_literal: true

# Physical onboarding requirements are store configuration, not a global
# Spree behaviour. The digital marketplace operator disables these rows only
# in the marketplace store through its store-scoped seller checklist.
class DisablePhysicalSellerOnboardingRequirements < ActiveRecord::Migration[8.1]
  def up
    # Intentionally no global update: other Spree stores may sell physical goods.
  end

  def down
    # No data changed by this migration.
  end
end
