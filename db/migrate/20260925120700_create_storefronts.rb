class CreateStorefronts < ActiveRecord::Migration[8.1]
  def change
    # A shop's public online store and how it takes click-and-collect orders.
    create_table :storefronts do |t|
      t.references :account, null: false, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :headline
      t.text :intro
      t.text :collection_note
      t.string :contact_phone
      t.boolean :show_stock_levels, null: false, default: true
      t.jsonb :collection_branch_ids, null: false, default: []
      t.timestamps
    end
    add_foreign_key :storefronts, :accounts, deferrable: :immediate
    enable_row_level_security :storefronts

    add_column :products, :online, :boolean, null: false, default: true

    # Where an order came from (the shop's own staff, the online store, or the API), and the unguessable
    # token in the link customers use to follow it.
    add_column :customer_orders, :source, :string, null: false, default: "shop"
    add_column :customer_orders, :tracking_token, :string
    add_index :customer_orders, :tracking_token, unique: true
    add_index :customer_orders, %i[ account_id source ]
  end
end
