class AddReporting < ActiveRecord::Migration[8.1]
  def up
    # What a line cost the shop when it was sold (all units, ex tax), so margins stay true after costs change.
    add_column :sale_lines, :cost_cents, :bigint, null: false, default: 0
    # Lines sold before this was recorded get today's cost: the best estimate there is. A data
    # migration spans every shop, so row-level security is lifted for it.
    Account.without_isolation { backfill_sale_line_costs }

    add_column :memberships, :daily_summary, :boolean, null: false, default: true

    add_index :sale_returns, %i[ account_id created_at ]
    add_index :supplier_invoices, %i[ account_id invoice_date ]
    add_index :shifts, %i[ account_id closed_at ]
  end

  def down
    remove_index :shifts, %i[ account_id closed_at ]
    remove_index :supplier_invoices, %i[ account_id invoice_date ]
    remove_index :sale_returns, %i[ account_id created_at ]
    remove_column :memberships, :daily_summary
    remove_column :sale_lines, :cost_cents
  end

  private
    def backfill_sale_line_costs
      execute <<~SQL
        UPDATE sale_lines SET cost_cents = ROUND(sale_lines.quantity * products.cost_cents)
        FROM products
        WHERE products.id = sale_lines.product_id AND sale_lines.product_unit_id IS NULL
      SQL
      execute <<~SQL
        UPDATE sale_lines SET cost_cents = ROUND(sale_lines.quantity * product_units.quantity * products.cost_cents)
        FROM product_units JOIN products ON products.id = product_units.product_id
        WHERE product_units.id = sale_lines.product_unit_id
      SQL
    end
end
