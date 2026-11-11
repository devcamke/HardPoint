class AddCreditHoldLiftToCustomers < ActiveRecord::Migration[8.1]
  def change
    # An owner or manager can lift a customer's credit hold (too long overdue) for a while, with a reason: until the
    # day it ends, the account takes sales on account again as if it weren't overdue.
    add_column :customers, :credit_hold_lifted_until, :date
    add_column :customers, :credit_hold_lifted_by_id, :bigint
    add_column :customers, :credit_hold_lift_reason, :string
  end
end
