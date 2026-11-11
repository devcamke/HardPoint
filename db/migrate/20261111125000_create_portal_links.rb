class CreatePortalLinks < ActiveRecord::Migration[8.1]
  def change
    # A link a customer opens without signing in to see what they owe, their open invoices and quotes, and pay with
    # M-Pesa. The token is random and opens only this customer's page at this shop.
    create_table :portal_links do |t|
      t.references :account, null: false, index: false
      t.references :customer, null: false
      t.references :created_by
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.integer :opened_count, null: false, default: 0
      t.datetime :last_opened_at
      t.timestamps
    end
    add_index :portal_links, %i[ account_id token ], unique: true

    safety_assured do
      add_foreign_key :portal_links, :accounts, deferrable: :immediate
      add_foreign_key :portal_links, :customers, deferrable: :immediate
    end
    enable_row_level_security :portal_links
  end
end
