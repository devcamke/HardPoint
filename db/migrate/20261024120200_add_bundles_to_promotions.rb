class AddBundlesToPromotions < ActiveRecord::Migration[8.1]
  def change
    # Mix and match: any bundle_quantity of the promotion's products together for bundle_price.
    add_column :promotions, :bundle_quantity, :integer
    add_column :promotions, :bundle_price_cents, :bigint
  end
end
