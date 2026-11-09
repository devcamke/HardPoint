class AddReorderLevelToStockLevels < ActiveRecord::Migration[8.1]
  def change
    # A branch's own reorder level for a product: a yard that sells cement by the pallet reorders at a
    # different point from a shop that sells it by the bag. Blank means the product's level applies.
    add_column :stock_levels, :reorder_level, :decimal, precision: 14, scale: 3
  end
end
