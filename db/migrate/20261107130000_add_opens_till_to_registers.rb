class AddOpensTillToRegisters < ActiveRecord::Migration[8.1]
  def change
    # A counter computer set to this till skips Home and goes straight into selling, for staff who sell
    # but don't see reports (docs/SIMPLIFY.md).
    add_column :registers, :opens_till, :boolean, null: false, default: false
  end
end
