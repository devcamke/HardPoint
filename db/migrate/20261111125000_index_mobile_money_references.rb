class IndexMobileMoneyReferences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # A typed M-Pesa code is looked up across the shop's payments, deposits and account payments (MobileMoneyCode),
  # at the till inside the sale's lock, so the lookup needs an index. Built concurrently so the tills keep selling.
  def change
    %i[ payments deposits customer_payments ].each do |table|
      add_index table, "account_id, upper(trim(reference))", name: "index_#{table}_on_account_and_reference",
        where: "reference IS NOT NULL", algorithm: :concurrently
    end
  end
end
