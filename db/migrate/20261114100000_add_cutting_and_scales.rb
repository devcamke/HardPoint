class AddCuttingAndScales < ActiveRecord::Migration[8.1]
  # Cutting: a product sold by the metre comes in lengths (a 6 m bar, a 100 m roll). stock_length says how long;
  # with it set, each sale is cut from an offcut that's long enough or, failing that, from a full length, and what's
  # left is kept as an offcut (a row here) or, under scrap_below, written off as cutting waste. A sale line's
  # cut_length is the length of each piece; its quantity stays the total.
  #
  # Weighing: a till can have a scale on a serial port, read from the browser (Web Serial).
  def change
    add_column :products, :stock_length, :decimal, precision: 12, scale: 3
    add_column :products, :scrap_below, :decimal, precision: 12, scale: 3, null: false, default: 0
    add_column :sale_lines, :cut_length, :decimal, precision: 12, scale: 3

    create_table :offcuts do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false
      t.references :product, null: false
      t.decimal :length, precision: 12, scale: 3, null: false
      t.timestamps
      t.check_constraint "length > 0", name: "offcuts_length_positive"
    end
    add_index :offcuts, %i[ account_id product_id branch_id ]

    safety_assured do
      add_foreign_key :offcuts, :accounts, deferrable: :immediate
      add_foreign_key :offcuts, :branches, deferrable: :immediate
      add_foreign_key :offcuts, :products, deferrable: :immediate
    end
    enable_row_level_security :offcuts

    add_column :registers, :scale_mode, :string, null: false, default: "none"
    add_column :registers, :scale_baud_rate, :integer, null: false, default: 9600
    add_column :registers, :scale_framing, :string, null: false, default: "8N1"
  end
end
