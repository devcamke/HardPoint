# Tool hire is no longer part of HardPoint. Its tools, agreements and terms go. What it left in the books
# stays: the "hire" customer orders with their deposits, payments, receipts and KRA eTIMS invoices, the
# "Tool hire" product their lines sold, texts in the SMS log and entries in the activity log.
class RemoveToolHire < ActiveRecord::Migration[8.1]
  def up
    # A data migration spans every shop, so row-level security is lifted for it.
    Account.without_isolation do
      execute "UPDATE accounts SET features = array_remove(features, 'tool_hire') WHERE 'tool_hire' = ANY(features)"
      # Texts keep their wording; only the link to the agreement, which no longer exists, is let go.
      execute "UPDATE sms_messages SET source_type = NULL, source_id = NULL WHERE source_type = 'HireAgreement'"
    end

    drop_table :hire_lines
    drop_table :hire_agreements
    drop_table :hire_items
    remove_column :accounts, :hire_terms
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Tool hire's tables and data were removed; restore from a backup taken before this migration"
  end
end
