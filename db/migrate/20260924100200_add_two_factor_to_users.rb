class AddTwoFactorToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string :two_factor_secret
      t.text :two_factor_recovery_codes
      t.datetime :two_factor_enabled_at
      t.bigint :two_factor_last_used_at
    end

    add_column :accounts, :require_two_factor_for_managers, :boolean, null: false, default: false
  end
end
