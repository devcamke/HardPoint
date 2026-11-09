class AddTaxRateToSaleLines < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Which of the shop's tax rates a line was sold under, not just the percentage: two rates can share 0%
    # (exempt and zero-rated) and KRA and the VAT return treat them differently.
    add_column :sale_lines, :tax_rate_id, :bigint
    up_only do
      # Lines sold before this get the shop's tax rate with their percentage, the default first where two share it,
      # which is what the eTIMS code and the VAT report assumed until now. Row-level security applies to the
      # migration's role too, so the backfill bypasses it for this one statement.
      safety_assured do
        transaction do
          execute <<~SQL
            SET LOCAL app.bypass_rls = 'on';
            UPDATE sale_lines
               SET tax_rate_id = (SELECT tax_rates.id FROM tax_rates
                                   WHERE tax_rates.account_id = sale_lines.account_id AND tax_rates.rate = sale_lines.tax_rate
                                   ORDER BY tax_rates."default" DESC, tax_rates.id LIMIT 1)
             WHERE sale_lines.tax_rate_id IS NULL
          SQL
        end
      end
    end
    add_index :sale_lines, :tax_rate_id, algorithm: :concurrently
    add_foreign_key :sale_lines, :tax_rates, deferrable: :immediate, validate: false
  end
end
