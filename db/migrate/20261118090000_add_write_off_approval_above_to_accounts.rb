class AddWriteOffApprovalAboveToAccounts < ActiveRecord::Migration[8.1]
  def change
    # Stock one person writes off by hand in a day, at cost, above this needs an owner's or manager's approval PIN;
    # KES 5,000 to start with, changed in Settings › Shop details.
    add_column :accounts, :write_off_approval_above_cents, :bigint, default: 500000, null: false
  end
end
