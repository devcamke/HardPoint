class CreateLoyalty < ActiveRecord::Migration[8.1]
  def change
    # A shop's points scheme: how many points a sale earns, and what a point is worth at the till.
    create_table :loyalty_programs do |t|
      t.references :account, null: false, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.decimal :points_per_100, precision: 8, scale: 2, null: false, default: 1
      t.bigint :point_value_cents, null: false, default: 100
      t.integer :min_redeem_points, null: false, default: 100
      t.timestamps
    end

    # Every change to a customer's points, so the balance is always explainable: earned on a sale,
    # spent at the till, taken back on a void or return, or adjusted by a manager with a reason.
    create_table :loyalty_entries do |t|
      t.references :account, null: false, index: false
      t.references :customer, null: false, index: false
      t.references :sale
      t.references :payment, index: { unique: true }
      t.references :sale_return
      t.references :creator
      t.string :kind, null: false
      t.integer :points, null: false
      t.string :note
      t.datetime :created_at, null: false
    end
    add_index :loyalty_entries, %i[ customer_id created_at ]
    add_index :loyalty_entries, %i[ account_id created_at ]

    add_column :payments, :points, :integer

    add_foreign_key :loyalty_programs, :accounts, deferrable: :immediate
    { customers: nil, sales: nil, payments: nil, sale_returns: nil }.each_key { add_foreign_key :loyalty_entries, _1, deferrable: :immediate }
    add_foreign_key :loyalty_entries, :accounts, deferrable: :immediate
    add_foreign_key :loyalty_entries, :users, column: :creator_id, deferrable: :immediate
    enable_row_level_security :loyalty_programs
    enable_row_level_security :loyalty_entries
  end
end
