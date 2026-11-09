class AddBranchToMemberships < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # A member of staff can be bound to one branch: they sell on its tills and see its sales, shifts, stock and
    # orders, and nothing of the other branches. Owners are never bound.
    add_column :memberships, :branch_id, :bigint
    add_index :memberships, :branch_id, algorithm: :concurrently
    add_foreign_key :memberships, :branches, deferrable: :immediate, validate: false
  end
end
