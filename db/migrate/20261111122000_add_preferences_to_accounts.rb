class AddPreferencesToAccounts < ActiveRecord::Migration[8.1]
  # The owner's choices that tune HardPoint to their shop (colour theme, quote validity, the till's payment buttons,
  # stock warnings, what quotes and invoices say). Typed and checked by Account::Preferences; anything not set
  # falls back to HardPoint's default.
  def change
    add_column :accounts, :preferences, :jsonb, null: false, default: {}
  end
end
