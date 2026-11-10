class CreateFundis < ActiveRecord::Migration[8.1]
  def change
    # The masons, plumbers, electricians and other tradespeople who bring customers to the shop, and earn a
    # commission on what those customers buy. Kept apart from customers: a fundi isn't the one paying.
    create_table :fundis do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.string :phone
      t.string :trade, null: false, default: "other"
      # Their own rate on everything, when the shop has agreed one; otherwise the category's or the shop's.
      t.decimal :commission_percent, precision: 5, scale: 2
      t.boolean :active, null: false, default: true
      t.string :note
      t.timestamps
    end
    add_index :fundis, %i[ account_id name ]

    # The commission ledger: earned on a completed sale, taken back by a void or a return, paid out. Rows are never
    # changed, so a fundi's statement always adds up; the balance owed is their sum.
    create_table :fundi_entries do |t|
      t.references :account, null: false, index: false
      t.references :fundi, null: false
      t.string :kind, null: false
      t.bigint :amount_cents, null: false
      t.bigint :sales_cents, null: false, default: 0
      t.references :source, polymorphic: true, null: false
      t.references :creator
      t.datetime :created_at, null: false
    end
    add_index :fundi_entries, %i[ account_id created_at ]

    create_table :fundi_payouts do |t|
      t.references :account, null: false, index: false
      t.references :fundi, null: false
      t.bigint :amount_cents, null: false
      t.string :payment_method, null: false
      t.string :reference
      t.references :cash_movement
      t.references :paid_by, null: false
      t.string :note
      t.datetime :created_at, null: false
    end
    add_index :fundi_payouts, %i[ account_id created_at ]

    # The tables are empty, so validating the keys locks nothing worth waiting for.
    safety_assured do
      add_foreign_key :fundis, :accounts, deferrable: :immediate
      add_foreign_key :fundi_entries, :accounts, deferrable: :immediate
      add_foreign_key :fundi_entries, :fundis, deferrable: :immediate
      add_foreign_key :fundi_payouts, :accounts, deferrable: :immediate
      add_foreign_key :fundi_payouts, :fundis, deferrable: :immediate
      add_foreign_key :fundi_payouts, :cash_movements, deferrable: :immediate
    end
    enable_row_level_security :fundis
    enable_row_level_security :fundi_entries
    enable_row_level_security :fundi_payouts

    # Rates: the shop's default, and a category's own (a subcategory without one uses its parent's).
    add_column :accounts, :fundi_commission_percent, :decimal, precision: 5, scale: 2, null: false, default: 0
    add_column :categories, :fundi_commission_percent, :decimal, precision: 5, scale: 2
  end
end
