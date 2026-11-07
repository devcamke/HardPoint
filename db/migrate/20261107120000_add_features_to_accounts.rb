class AddFeaturesToAccounts < ActiveRecord::Migration[8.1]
  def up
    # The optional features a shop has switched on (Account::Features). New shops start with deliveries.
    add_column :accounts, :features, :string, array: true, null: false, default: [ "deliveries" ]
    # When the owner last looked at Settings › Features, which ticks off the setup checklist step.
    add_column :accounts, :features_reviewed_at, :datetime

    # Existing shops keep every feature they have records for, so nothing they use disappears.
    # A data migration spans every shop, so row-level security is lifted for it.
    Account.reset_column_information
    Account.without_isolation do
      Account.find_each do |account|
        account.update_columns(features: (Account::Features::DEFAULTS + account.features_in_use).uniq.sort)
      end
    end
  end

  def down
    remove_column :accounts, :features_reviewed_at
    remove_column :accounts, :features
  end
end
