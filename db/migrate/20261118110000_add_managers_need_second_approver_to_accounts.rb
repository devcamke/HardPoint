class AddManagersNeedSecondApproverToAccounts < ActiveRecord::Migration[8.1]
  def change
    # A manager's own voids, discounts, payouts, write-offs and purchases need an owner's or another manager's
    # approval PIN. Off for the shops there already are, so nothing changes under them; a new shop starts with it on.
    add_column :accounts, :managers_need_second_approver, :boolean, default: false, null: false
  end
end
