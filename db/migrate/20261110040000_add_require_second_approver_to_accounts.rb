class AddRequireSecondApproverToAccounts < ActiveRecord::Migration[8.1]
  def change
    # On, an owner's or manager's own void, discount or credit needs another approver's PIN.
    add_column :accounts, :require_second_approver, :boolean, default: false, null: false
  end
end
