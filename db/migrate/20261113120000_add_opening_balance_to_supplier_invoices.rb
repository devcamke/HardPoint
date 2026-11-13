# What the shop already owed a supplier when it moved to HardPoint comes across as an invoice with nothing
# behind it (SupplierImport). The flag keeps it out of purchases: the VAT report and the QuickBooks stock lines.
class AddOpeningBalanceToSupplierInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :supplier_invoices, :opening_balance, :boolean, null: false, default: false
  end
end
