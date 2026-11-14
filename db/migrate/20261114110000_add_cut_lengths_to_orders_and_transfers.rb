class AddCutLengthsToOrdersAndTransfers < ActiveRecord::Migration[8.1]
  # A quote or order can say how a product cut to length is to be cut (the length of each piece, as on a sale line),
  # and a transfer remembers the offcuts that travelled with it, so they're listed again where they arrive.
  def change
    add_column :customer_order_lines, :cut_length, :decimal, precision: 12, scale: 3
    add_column :stock_transfer_lines, :offcut_lengths, :decimal, precision: 12, scale: 3, array: true, null: false, default: []
  end
end
