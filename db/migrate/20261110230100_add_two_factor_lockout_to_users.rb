class AddTwoFactorLockoutToUsers < ActiveRecord::Migration[8.1]
  def change
    # Wrong two-factor codes in a row; after too many, codes aren't accepted until two_factor_locked_until.
    add_column :users, :failed_two_factor_attempts, :integer, null: false, default: 0
    add_column :users, :two_factor_locked_until, :datetime
  end
end
