class AddReceivedQuantitiesToStockTransfers < ActiveRecord::Migration[8.1]
  def change
    # What actually arrived of each line, filled in when the transfer is received; blank while in transit.
    add_column :stock_transfer_lines, :received_quantity, :decimal, precision: 14, scale: 3
    # What became of anything short: "lost" on the way (written off at the receiving branch) or "returned"
    # to the sender's stock because it never left. Blank when everything arrived.
    add_column :stock_transfers, :shortfall, :string
  end
end
