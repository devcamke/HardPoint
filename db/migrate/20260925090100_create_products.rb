class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :account, null: false, index: false
      t.references :category
      t.references :brand
      t.references :unit, null: false
      t.references :tax_rate
      t.string :name, null: false
      t.string :sku, null: false
      t.text :description
      t.bigint :cost_cents, null: false, default: 0
      t.bigint :price_cents, null: false
      t.decimal :reorder_level, precision: 14, scale: 3, null: false, default: 0
      t.boolean :track_stock, null: false, default: true
      t.boolean :serialized, null: false, default: false
      t.boolean :kit, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :products, %i[ account_id sku ], unique: true
    add_index :products, :name, using: :gin, opclass: :gin_trgm_ops
    add_index :products, :sku, using: :gin, opclass: :gin_trgm_ops, name: "index_products_on_sku_trigram"

    # Pack sizes: a box of 100 screws is 100 of the product's base unit, with its own price.
    create_table :product_units do |t|
      t.references :account, null: false, index: false
      t.references :product, null: false, index: false
      t.references :unit, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.bigint :price_cents
      t.timestamps
    end
    add_index :product_units, %i[ product_id unit_id ], unique: true

    create_table :barcodes do |t|
      t.references :account, null: false, index: false
      t.references :product, null: false
      t.references :product_unit
      t.string :code, null: false
      t.timestamps
    end
    add_index :barcodes, %i[ account_id code ], unique: true

    create_table :kit_components do |t|
      t.references :account, null: false, index: false
      t.references :kit, null: false, index: false
      t.references :component, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.timestamps
    end
    add_index :kit_components, %i[ kit_id component_id ], unique: true

    # Prices that differ from the product's retail price: per price list (contractor, wholesale),
    # and/or from a minimum quantity. A row without a price list is a retail quantity break.
    create_table :price_list_items do |t|
      t.references :account, null: false, index: false
      t.references :price_list
      t.references :product, null: false, index: false
      t.decimal :min_quantity, precision: 14, scale: 3, null: false, default: 1
      t.bigint :price_cents, null: false
      t.timestamps
    end
    add_index :price_list_items, %i[ product_id price_list_id min_quantity ], unique: true, nulls_not_distinct: true

    add_foreign_key :products, :accounts, deferrable: :immediate
    add_foreign_key :products, :categories, deferrable: :immediate
    add_foreign_key :products, :brands, deferrable: :immediate
    add_foreign_key :products, :units, deferrable: :immediate
    add_foreign_key :products, :tax_rates, deferrable: :immediate
    add_foreign_key :product_units, :accounts, deferrable: :immediate
    add_foreign_key :product_units, :products, deferrable: :immediate
    add_foreign_key :product_units, :units, deferrable: :immediate
    add_foreign_key :barcodes, :accounts, deferrable: :immediate
    add_foreign_key :barcodes, :products, deferrable: :immediate
    add_foreign_key :barcodes, :product_units, deferrable: :immediate
    add_foreign_key :kit_components, :accounts, deferrable: :immediate
    add_foreign_key :kit_components, :products, column: :kit_id, deferrable: :immediate
    add_foreign_key :kit_components, :products, column: :component_id, deferrable: :immediate
    add_foreign_key :price_list_items, :accounts, deferrable: :immediate
    add_foreign_key :price_list_items, :price_lists, deferrable: :immediate
    add_foreign_key :price_list_items, :products, deferrable: :immediate

    %i[ products product_units barcodes kit_components price_list_items ].each { |table| enable_row_level_security table }
  end
end
