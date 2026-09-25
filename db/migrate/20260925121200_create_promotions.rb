class CreatePromotions < ActiveRecord::Migration[8.1]
  def change
    # Offers that change prices for a while: a percentage off, or "buy 10, get 1 free", on chosen
    # products or whole categories, at all branches or some.
    create_table :promotions do |t|
      t.references :account, null: false, index: false
      t.references :creator
      t.string :name, null: false
      t.string :kind, null: false
      t.decimal :percent_off, precision: 5, scale: 2
      t.decimal :buy_quantity, precision: 14, scale: 3
      t.decimal :free_quantity, precision: 14, scale: 3
      t.bigint :product_ids, array: true, null: false, default: []
      t.bigint :category_ids, array: true, null: false, default: []
      t.bigint :branch_ids, array: true, null: false, default: []
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :promotions, %i[ account_id ends_on starts_on ]

    # What a promotion took off a line, kept apart from discounts given by hand.
    add_reference :sale_lines, :promotion, index: true
    add_column :sale_lines, :promotion_discount_cents, :bigint, null: false, default: 0
    add_reference :customer_order_lines, :promotion, index: true

    add_foreign_key :promotions, :accounts, deferrable: :immediate
    add_foreign_key :promotions, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :sale_lines, :promotions, deferrable: :immediate
    add_foreign_key :customer_order_lines, :promotions, deferrable: :immediate
    enable_row_level_security :promotions
  end
end
