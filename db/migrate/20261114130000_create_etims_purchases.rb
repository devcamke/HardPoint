class CreateEtimsPurchases < ActiveRecord::Migration[8.1]
  # Invoices suppliers have issued to the shop's PIN, as KRA eTIMS holds them. A branch's control unit asks KRA for
  # what's new; each invoice waits here until someone receives its goods, records it as an invoice, or sets it aside.
  def change
    create_table :etims_purchases do |t|
      t.references :account, null: false, index: false
      t.references :device, null: false, index: false
      t.references :supplier
      t.references :goods_receipt
      t.references :supplier_invoice
      t.references :handled_by
      t.string :supplier_tin, null: false
      t.string :supplier_name
      t.string :supplier_bhf_id, null: false, default: "00"
      t.string :invoice_number, null: false
      t.string :receipt_type, null: false, default: "S"
      t.date :sales_date, null: false
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.jsonb :items, null: false, default: []
      t.string :status, null: false, default: "new"
      t.string :note
      t.datetime :handled_at
      t.timestamps
    end
    add_index :etims_purchases, %i[ device_id supplier_tin supplier_bhf_id invoice_number receipt_type ], unique: true, name: "index_etims_purchases_on_device_and_supplier_invoice"
    add_index :etims_purchases, %i[ account_id status sales_date ]

    safety_assured do
      add_foreign_key :etims_purchases, :accounts, deferrable: :immediate
      add_foreign_key :etims_purchases, :etims_devices, column: :device_id, deferrable: :immediate
      add_foreign_key :etims_purchases, :suppliers, deferrable: :immediate
      add_foreign_key :etims_purchases, :goods_receipts, deferrable: :immediate
      add_foreign_key :etims_purchases, :supplier_invoices, deferrable: :immediate
    end
    enable_row_level_security :etims_purchases

    add_column :etims_devices, :purchases_checked_at, :datetime
    add_column :etims_devices, :purchases_error, :string
  end
end
