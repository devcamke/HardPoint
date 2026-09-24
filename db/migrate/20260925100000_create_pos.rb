class CreatePos < ActiveRecord::Migration[8.1]
  def change
    change_table :accounts do |t|
      # Cashiers may discount up to this much of a line or sale; more needs a manager's approval PIN.
      t.decimal :max_cashier_discount_percent, precision: 5, scale: 2, null: false, default: 5
      t.text :receipt_footer
    end
    add_column :branches, :code, :string
    add_column :products, :quick_pick, :boolean, null: false, default: false
    # A second PIN that lets an owner or manager approve something at a cashier's till. It never signs anyone in.
    add_column :memberships, :approval_pin_digest, :string

    create_table :customers do |t|
      t.references :account, null: false, index: false
      t.references :price_list
      t.string :name, null: false
      t.string :phone
      t.string :email
      t.string :tax_pin
      t.bigint :credit_limit_cents, null: false, default: 0
      t.text :notes
      t.timestamps
    end
    add_index :customers, %i[ account_id name ]
    add_index :customers, :name, using: :gin, opclass: :gin_trgm_ops
    add_index :customers, :phone

    create_table :shifts do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false
      t.references :register, null: false, index: false
      t.references :opened_by, null: false
      t.references :closed_by
      t.string :status, null: false, default: "open"
      t.bigint :opening_float_cents, null: false, default: 0
      t.bigint :expected_cash_cents
      t.bigint :counted_cash_cents
      t.string :note
      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.timestamps
    end
    add_index :shifts, :register_id, unique: true, where: "status = 'open'", name: "index_shifts_one_open_per_register"
    add_index :shifts, %i[ register_id opened_at ]

    create_table :cash_movements do |t|
      t.references :account, null: false, index: false
      t.references :shift, null: false
      t.references :creator
      t.string :kind, null: false
      t.bigint :amount_cents, null: false
      t.string :reason, null: false
      t.datetime :created_at, null: false
    end

    create_table :sales do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.references :register, null: false
      t.references :shift, null: false
      t.references :customer
      t.references :cashier, null: false
      t.references :discount_approver
      t.decimal :approved_discount_percent, precision: 5, scale: 2
      t.references :voided_by
      t.string :status, null: false, default: "open"
      t.integer :number
      t.bigint :discount_cents, null: false, default: 0
      t.bigint :subtotal_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.string :note
      t.string :void_reason
      t.datetime :completed_at
      t.datetime :voided_at
      t.timestamps
    end
    add_index :sales, %i[ branch_id number ], unique: true, where: "number IS NOT NULL"
    add_index :sales, %i[ account_id completed_at ]
    add_index :sales, %i[ register_id status ]

    create_table :sale_lines do |t|
      t.references :account, null: false, index: false
      t.references :sale, null: false
      t.references :product, null: false
      t.references :product_unit
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.bigint :unit_price_cents, null: false
      t.bigint :discount_cents, null: false, default: 0
      t.decimal :tax_rate, precision: 5, scale: 2, null: false, default: 0
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.string :serial_number
      t.timestamps
    end

    create_table :payments do |t|
      t.references :account, null: false, index: false
      t.references :sale, null: false
      t.string :tender, null: false
      t.bigint :amount_cents, null: false
      t.bigint :tendered_cents
      t.string :reference
      t.datetime :created_at, null: false
    end

    create_table :sale_returns do |t|
      t.references :account, null: false, index: false
      t.references :sale, null: false
      t.references :branch, null: false, index: false
      t.references :shift, null: false
      t.references :creator, null: false
      t.references :approver
      t.integer :number, null: false
      t.string :refund_method, null: false
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
      t.string :reason
      t.datetime :created_at, null: false
    end
    add_index :sale_returns, %i[ branch_id number ], unique: true

    create_table :sale_return_lines do |t|
      t.references :account, null: false, index: false
      t.references :sale_return, null: false
      t.references :sale_line, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.boolean :restock, null: false, default: true
      t.bigint :total_cents, null: false, default: 0
      t.bigint :tax_cents, null: false, default: 0
    end

    # Receipt and return numbers run without gaps per branch.
    create_table :document_sequences do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.string :kind, null: false
      t.integer :last_number, null: false, default: 0
      t.timestamps
    end
    add_index :document_sequences, %i[ branch_id kind ], unique: true

    {
      customers: %i[ accounts price_lists ],
      shifts: %i[ accounts branches registers ],
      cash_movements: %i[ accounts shifts ],
      sales: %i[ accounts branches registers shifts customers ],
      sale_lines: %i[ accounts sales products product_units ],
      payments: %i[ accounts sales ],
      sale_returns: %i[ accounts sales branches shifts ],
      sale_return_lines: %i[ accounts sale_returns sale_lines ],
      document_sequences: %i[ accounts branches ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end

    add_foreign_key :shifts, :users, column: :opened_by_id, deferrable: :immediate
    add_foreign_key :shifts, :users, column: :closed_by_id, deferrable: :immediate
    add_foreign_key :cash_movements, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :sales, :users, column: :cashier_id, deferrable: :immediate
    add_foreign_key :sales, :users, column: :discount_approver_id, deferrable: :immediate
    add_foreign_key :sales, :users, column: :voided_by_id, deferrable: :immediate
    add_foreign_key :sale_returns, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :sale_returns, :users, column: :approver_id, deferrable: :immediate
  end
end
