class CreatePurchasing < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.string :tax_pin
      t.string :address
      t.integer :payment_terms_days, null: false, default: 30
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end
    add_index :suppliers, %i[ account_id name ], unique: true
    add_index :suppliers, :name, using: :gin, opclass: :gin_trgm_ops

    # Who supplies what, at what cost, how fast, and in what minimum quantity.
    create_table :supplier_products do |t|
      t.references :account, null: false, index: false
      t.references :supplier, null: false, index: false
      t.references :product, null: false
      t.string :supplier_sku
      t.bigint :cost_cents, null: false, default: 0
      t.integer :lead_time_days, null: false, default: 7
      t.decimal :min_order_quantity, precision: 14, scale: 3, null: false, default: 1
      t.boolean :preferred, null: false, default: false
      t.timestamps
    end
    add_index :supplier_products, %i[ supplier_id product_id ], unique: true

    create_table :purchase_orders do |t|
      t.references :account, null: false, index: false
      t.references :supplier, null: false
      t.references :branch, null: false, index: false
      t.references :creator
      t.integer :number, null: false
      t.string :status, null: false, default: "draft"
      t.date :expected_on
      t.string :note
      t.bigint :total_cents, null: false, default: 0
      t.datetime :sent_at
      t.timestamps
    end
    add_index :purchase_orders, %i[ branch_id number ], unique: true
    add_index :purchase_orders, %i[ account_id status ]

    create_table :purchase_order_lines do |t|
      t.references :account, null: false, index: false
      t.references :purchase_order, null: false, index: false
      t.references :product, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :received_quantity, precision: 14, scale: 3, null: false, default: 0
      t.bigint :unit_cost_cents, null: false, default: 0
      t.timestamps
    end
    add_index :purchase_order_lines, %i[ purchase_order_id product_id ], unique: true

    # A goods received note (GRN): what actually arrived, at what cost, with extra costs
    # (transport, duty) spread over the lines so stock carries its true landed cost.
    create_table :goods_receipts do |t|
      t.references :account, null: false, index: false
      t.references :supplier, null: false
      t.references :purchase_order
      t.references :branch, null: false, index: false
      t.references :receiver
      t.integer :number, null: false
      t.string :supplier_reference
      t.bigint :extra_costs_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :note
      t.datetime :created_at, null: false
    end
    add_index :goods_receipts, %i[ branch_id number ], unique: true

    create_table :goods_receipt_lines do |t|
      t.references :account, null: false, index: false
      t.references :goods_receipt, null: false
      t.references :purchase_order_line
      t.references :product, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.bigint :unit_cost_cents, null: false
      t.bigint :landed_unit_cost_cents, null: false, default: 0
    end

    create_table :supplier_invoices do |t|
      t.references :account, null: false, index: false
      t.references :supplier, null: false, index: false
      t.references :goods_receipt
      t.references :creator
      t.string :number, null: false
      t.date :invoice_date, null: false
      t.date :due_date, null: false
      t.bigint :total_cents, null: false
      t.bigint :tax_cents, null: false, default: 0
      t.string :note
      t.timestamps
    end
    add_index :supplier_invoices, %i[ supplier_id number ], unique: true
    add_index :supplier_invoices, %i[ supplier_id due_date ]

    create_table :supplier_payments do |t|
      t.references :account, null: false, index: false
      t.references :supplier, null: false
      t.references :creator
      t.date :paid_on, null: false
      t.bigint :amount_cents, null: false
      t.string :payment_method, null: false
      t.string :reference
      t.string :note
      t.datetime :created_at, null: false
    end

    {
      suppliers: %i[ accounts ],
      supplier_products: %i[ accounts suppliers products ],
      purchase_orders: %i[ accounts suppliers branches ],
      purchase_order_lines: %i[ accounts purchase_orders products ],
      goods_receipts: %i[ accounts suppliers purchase_orders branches ],
      goods_receipt_lines: %i[ accounts goods_receipts purchase_order_lines products ],
      supplier_invoices: %i[ accounts suppliers goods_receipts ],
      supplier_payments: %i[ accounts suppliers ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :purchase_orders, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :goods_receipts, :users, column: :receiver_id, deferrable: :immediate
    add_foreign_key :supplier_invoices, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :supplier_payments, :users, column: :creator_id, deferrable: :immediate
  end
end
