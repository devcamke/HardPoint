class CreateToolHire < ActiveRecord::Migration[8.1]
  def change
    # Each physical tool a shop hires out.
    create_table :hire_items do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false
      t.string :name, null: false
      t.string :asset_tag, null: false
      t.string :serial_number
      t.bigint :daily_rate_cents, null: false
      t.bigint :weekly_rate_cents
      t.bigint :deposit_cents, null: false, default: 0
      t.string :status, null: false, default: "available"
      t.text :notes
      t.timestamps
    end
    add_index :hire_items, %i[ account_id asset_tag ], unique: true
    add_index :hire_items, %i[ account_id status ]

    # A hire: who has which tools, from when, until when. Its money (deposit, charges) lives on a
    # customer order of source "hire", settled at the till like any order.
    create_table :hire_agreements do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: false
      t.references :customer, null: false
      t.references :customer_order, null: false, index: { unique: true }
      t.references :creator
      t.integer :number, null: false
      t.string :status, null: false, default: "out"
      t.string :id_number
      t.string :site
      t.string :note
      t.datetime :started_at, null: false
      t.datetime :due_back_at, null: false
      t.datetime :returned_at
      t.datetime :reminded_at
      t.timestamps
    end
    add_index :hire_agreements, %i[ branch_id number ], unique: true
    add_index :hire_agreements, %i[ account_id status due_back_at ]

    create_table :hire_lines do |t|
      t.references :account, null: false, index: false
      t.references :hire_agreement, null: false
      t.references :hire_item, null: false
      t.bigint :daily_rate_cents, null: false
      t.bigint :weekly_rate_cents
      t.datetime :returned_at
      t.integer :days_charged
      t.bigint :charge_cents
      t.bigint :damage_cents, null: false, default: 0
      t.string :damage_note
      t.string :condition_note
      t.timestamps
    end

    # What a line is for, beyond the product's name ("Concrete mixer MIX-01, 4 days").
    add_column :customer_order_lines, :detail, :string
    add_column :sale_lines, :detail, :string

    {
      hire_items: %i[ accounts branches ],
      hire_agreements: %i[ accounts branches customers customer_orders ],
      hire_lines: %i[ accounts hire_agreements hire_items ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :hire_agreements, :users, column: :creator_id, deferrable: :immediate
    add_index :hire_lines, :account_id
    add_index :hire_items, :account_id
  end
end
