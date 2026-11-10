class AddQzSigningKeysToAccounts < ActiveRecord::Migration[8.1]
  def change
    # Each shop signs its own QZ Tray print requests with its own key, so one shop's till can never obtain a
    # signature another shop's QZ Tray would trust (Account::QzSigning). Made the first time a till asks.
    add_column :accounts, :qz_private_key, :text # encrypted
    add_column :accounts, :qz_certificate, :text
  end
end
