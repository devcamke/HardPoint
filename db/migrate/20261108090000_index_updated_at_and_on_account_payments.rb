# For the API's updated_since syncs and the offline till's catalogue version (both read the newest updated_at per shop),
# and for balances, which add up a shop's payments on account.
class IndexUpdatedAtAndOnAccountPayments < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    %i[ sales products customers stock_levels customer_orders ].each do |table|
      add_index table, %i[ account_id updated_at ], algorithm: :concurrently, if_not_exists: true
    end
    add_index :payments, %i[ account_id sale_id ], where: "tender = 'on_account'", name: "index_payments_on_account_sales", algorithm: :concurrently, if_not_exists: true
  end
end
