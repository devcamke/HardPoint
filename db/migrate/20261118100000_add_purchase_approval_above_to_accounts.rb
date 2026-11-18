class AddPurchaseApprovalAboveToAccounts < ActiveRecord::Migration[8.1]
  def change
    # A purchase order above this, or goods received in a day with no order behind them above it, needs an owner's or
    # manager's approval PIN; KES 20,000 to start with, changed in Settings › Shop details.
    add_column :accounts, :purchase_approval_above_cents, :bigint, default: 2000000, null: false
  end
end
