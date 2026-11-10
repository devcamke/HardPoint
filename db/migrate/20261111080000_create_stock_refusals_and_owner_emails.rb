class CreateStockRefusalsAndOwnerEmails < ActiveRecord::Migration[8.1]
  def change
    # Each time the till turned a sale away because the stock wasn't on the shelf: what the owner would have sold
    # with the delivery in. Read by the morning email; quantities are in the product's base unit.
    create_table :stock_refusals do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false
      t.references :product, null: false
      t.references :user
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.decimal :on_hand, precision: 14, scale: 3, null: false
      t.datetime :created_at, null: false
    end
    add_index :stock_refusals, %i[ account_id created_at ]
    # The table is empty, so validating the keys locks nothing worth waiting for.
    safety_assured do
      add_foreign_key :stock_refusals, :accounts, deferrable: :immediate
      add_foreign_key :stock_refusals, :branches, deferrable: :immediate
      add_foreign_key :stock_refusals, :products, deferrable: :immediate
    end
    enable_row_level_security :stock_refusals

    # Which of the owner's emails each person wants, beside the daily summary.
    add_column :memberships, :weekly_summary, :boolean, null: false, default: true
    add_column :memberships, :alert_emails, :boolean, null: false, default: true

    # Instant emails only for what's worth stopping for; the owner sets how big that is.
    add_column :accounts, :alert_shift_short_above_cents, :bigint, null: false, default: 2_000_00
    add_column :accounts, :alert_void_above_cents, :bigint, null: false, default: 10_000_00
    add_column :accounts, :alert_count_loss_above_cents, :bigint, null: false, default: 5_000_00
  end
end
