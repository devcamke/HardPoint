class AddApprovedDiscountCentsToSales < ActiveRecord::Migration[8.1]
  # A manager's approval covers the discounts on the sale when they gave it: no bigger a share (approved_discount_percent)
  # and no more money (this), so approving 50% off one cheap line doesn't let the cashier take 50% off the whole sale.
  def change
    add_column :sales, :approved_discount_cents, :bigint
  end
end
