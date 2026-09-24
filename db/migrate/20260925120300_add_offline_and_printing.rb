class AddOfflineAndPrinting < ActiveRecord::Migration[8.1]
  def change
    # Sales rung up while the till was offline carry the ID the till gave them, so sending one
    # twice records it once, and the time they actually happened.
    add_column :sales, :offline_uuid, :uuid
    add_column :sales, :offline_receipt_number, :string
    add_index :sales, %i[ account_id offline_uuid ], unique: true, where: "offline_uuid IS NOT NULL"

    # How each till prints: through the browser's print dialog (silent in a kiosk-mode browser),
    # or straight to a receipt printer through QZ Tray, which also opens the cash drawer.
    add_column :registers, :print_mode, :string, null: false, default: "browser"
    add_column :registers, :printer_name, :string
    add_column :registers, :receipt_width, :integer, null: false, default: 48
  end
end
