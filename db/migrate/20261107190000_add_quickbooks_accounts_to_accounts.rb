class AddQuickbooksAccountsToAccounts < ActiveRecord::Migration[8.1]
  def change
    # The QuickBooks Online account names the shop's export posts to, where they differ from the defaults.
    add_column :accounts, :quickbooks_accounts, :jsonb, null: false, default: {}
  end
end
