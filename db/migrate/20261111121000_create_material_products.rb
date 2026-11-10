class CreateMaterialProducts < ActiveRecord::Migration[8.1]
  def change
    # The shop's own product for each of the material calculator's materials (cement, sand, Y12 bar…), set once.
    create_table :material_products do |t|
      t.references :account, null: false, index: false
      t.string :material, null: false
      t.references :product, null: false
      t.references :product_unit
      t.decimal :factor, precision: 12, scale: 4, null: false, default: 1
      t.timestamps
    end
    add_index :material_products, %i[ account_id material ], unique: true
    # The table is empty, so validating the keys locks nothing worth waiting for.
    safety_assured do
      add_foreign_key :material_products, :accounts, deferrable: :immediate
      add_foreign_key :material_products, :products, deferrable: :immediate
      add_foreign_key :material_products, :product_units, deferrable: :immediate
    end
    enable_row_level_security :material_products
  end
end
