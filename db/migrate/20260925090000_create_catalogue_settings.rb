class CreateCatalogueSettings < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_table :categories do |t|
      t.references :account, null: false, index: false
      t.references :parent
      t.string :name, null: false
      t.timestamps
    end
    add_index :categories, %i[ account_id name ], unique: true

    create_table :brands do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :brands, %i[ account_id name ], unique: true

    create_table :units do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.string :abbreviation, null: false
      t.boolean :fractional, null: false, default: false
      t.timestamps
    end
    add_index :units, %i[ account_id name ], unique: true

    create_table :tax_rates do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.decimal :rate, precision: 5, scale: 2, null: false
      t.boolean :default, null: false, default: false
      t.timestamps
    end
    add_index :tax_rates, %i[ account_id name ], unique: true

    create_table :price_lists do |t|
      t.references :account, null: false, index: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :price_lists, %i[ account_id name ], unique: true

    add_foreign_key :categories, :accounts, deferrable: :immediate
    add_foreign_key :categories, :categories, column: :parent_id, deferrable: :immediate
    %i[ brands units tax_rates price_lists ].each { |table| add_foreign_key table, :accounts, deferrable: :immediate }

    %i[ categories brands units tax_rates price_lists ].each { |table| enable_row_level_security table }
  end
end
