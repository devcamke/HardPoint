class CreateCustomerAccounts < ActiveRecord::Migration[8.1]
  def change
    change_table :customers do |t|
      t.integer :payment_terms_days, null: false, default: 30
      t.string :address
    end

    # One document from quote to collection: a quote (with a validity date) becomes an order,
    # the order can take deposits and be marked ready, and it's collected by ringing it up at a till.
    create_table :customer_orders do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.references :customer, null: false
      t.references :creator
      t.integer :number, null: false
      t.string :status, null: false, default: "quote"
      t.date :valid_until
      t.date :needed_by
      t.string :note
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.datetime :ordered_at
      t.datetime :collected_at
      t.timestamps
    end
    add_index :customer_orders, %i[ branch_id number ], unique: true
    add_index :customer_orders, %i[ account_id status ]

    create_table :customer_order_lines do |t|
      t.references :account, null: false, index: false
      t.references :customer_order, null: false
      t.references :product, null: false
      t.references :product_unit
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.bigint :unit_price_cents, null: false, default: 0
      t.decimal :tax_rate, precision: 5, scale: 2, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.timestamps
    end

    # Money paid towards an order before collection. Negative when a deposit is refunded.
    # Cash deposits belong to the shift whose drawer took (or paid out) the cash.
    create_table :deposits do |t|
      t.references :account, null: false, index: false
      t.references :customer_order, null: false
      t.references :shift
      t.references :creator
      t.bigint :amount_cents, null: false
      t.string :tender, null: false
      t.string :reference
      t.datetime :created_at, null: false
    end

    # A customer paying off their account. Payments settle the oldest account sales first.
    create_table :customer_payments do |t|
      t.references :account, null: false, index: false
      t.references :customer, null: false
      t.references :shift
      t.references :creator
      t.date :paid_on, null: false
      t.bigint :amount_cents, null: false
      t.string :payment_method, null: false
      t.string :reference
      t.string :note
      t.datetime :created_at, null: false
    end

    create_table :delivery_notes do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.references :sale, null: false
      t.references :creator
      t.integer :number, null: false
      t.string :status, null: false, default: "pending"
      t.string :address, null: false
      t.string :contact_phone
      t.string :driver_name
      t.string :vehicle
      t.string :received_by
      t.string :note
      t.datetime :dispatched_at
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :delivery_notes, %i[ branch_id number ], unique: true
    add_index :delivery_notes, %i[ account_id status ]

    change_table :sales do |t|
      t.references :customer_order
      t.references :credit_approver
    end
    add_column :sale_lines, :customer_order_line_id, :bigint
    add_index :sale_lines, :customer_order_line_id

    {
      customer_orders: %i[ accounts branches customers ],
      customer_order_lines: %i[ accounts customer_orders products product_units ],
      deposits: %i[ accounts customer_orders shifts ],
      customer_payments: %i[ accounts customers shifts ],
      delivery_notes: %i[ accounts branches sales ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :customer_orders, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :deposits, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :customer_payments, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :delivery_notes, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :sales, :customer_orders, deferrable: :immediate
    add_foreign_key :sales, :users, column: :credit_approver_id, deferrable: :immediate
    add_foreign_key :sale_lines, :customer_order_lines, deferrable: :immediate
  end
end
