class CreateCurrencies < ActiveRecord::Migration[8.1]
  def change
    # Other currencies a shop deals in, with what one unit is worth in the shop's own currency.
    # The rate used is copied onto every payment, order and receipt, so changing it never
    # rewrites history.
    create_table :currencies do |t|
      t.references :account, null: false, index: false
      t.string :code, null: false
      t.decimal :rate, precision: 18, scale: 8, null: false
      t.boolean :accepted_at_till, null: false, default: true
      t.references :updater
      t.timestamps
    end
    add_index :currencies, %i[ account_id code ], unique: true

    # Foreign cash at the till: what was handed over, in which currency, at what rate. The payment's
    # amount and tendered stay in the shop's currency; change is given in the shop's currency.
    add_column :payments, :currency, :string
    add_column :payments, :foreign_tendered_cents, :bigint
    add_column :payments, :exchange_rate, :decimal, precision: 18, scale: 8

    # Foreign notes in the drawer at close: { "USD" => { "expected" => cents, "counted" => cents } }.
    add_column :shifts, :foreign_cash, :jsonb, null: false, default: {}

    # Suppliers who invoice in another currency: their orders, invoices and payments are in it.
    add_column :suppliers, :currency, :string
    add_column :purchase_orders, :exchange_rate, :decimal, precision: 18, scale: 8
    add_column :goods_receipts, :exchange_rate, :decimal, precision: 18, scale: 8
    add_column :supplier_invoices, :exchange_rate, :decimal, precision: 18, scale: 8

    add_foreign_key :currencies, :accounts, deferrable: :immediate
    add_foreign_key :currencies, :users, column: :updater_id, deferrable: :immediate
    enable_row_level_security :currencies
  end
end
