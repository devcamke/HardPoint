# Loyalty points are no longer part of HardPoint. The points scheme and every customer's points ledger go.
# What they left in the books stays: payments made with points (tender "points", with how many were used)
# on their sales, receipts and KRA eTIMS invoices, texts in the SMS log, and entries in the activity log.
class RemoveLoyaltyPoints < ActiveRecord::Migration[8.1]
  def up
    # A data migration spans every shop, so row-level security is lifted for it.
    Account.without_isolation do
      execute "UPDATE accounts SET features = array_remove(features, 'loyalty') WHERE 'loyalty' = ANY(features)"
    end

    drop_table :loyalty_entries
    drop_table :loyalty_programs
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Loyalty points and their ledger were removed; restore from a backup taken before this migration"
  end
end
