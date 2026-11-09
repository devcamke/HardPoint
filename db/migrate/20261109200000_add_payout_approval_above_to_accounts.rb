class AddPayoutApprovalAboveToAccounts < ActiveRecord::Migration[8.1]
  def change
    # A payout from a till's drawer above this needs an owner's or manager's approval PIN; KES 5,000 to start with,
    # changed in Settings › Shop details.
    add_column :accounts, :payout_approval_above_cents, :bigint, default: 500000, null: false
  end
end
