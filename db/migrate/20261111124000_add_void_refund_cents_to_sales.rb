class AddVoidRefundCentsToSales < ActiveRecord::Migration[8.1]
  # What a void handed back (Sale#void_refund_cents), kept as it was at the void. Voids before this column have none:
  # they keep counting as they did then, so no drawer or customer balance changes after the fact.
  def change
    add_column :sales, :void_refund_cents, :bigint
  end
end
