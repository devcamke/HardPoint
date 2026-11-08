class AddPlanAddOnsAndOneOffInvoices < ActiveRecord::Migration[8.1]
  def change
    change_table :accounts, bulk: true do |t|
      # Branches and tills bought on top of the plan's allowance, each priced per month by the plan.
      t.integer :extra_branches, null: false, default: 0
      t.integer :extra_registers, null: false, default: 0
      t.string :billing_interval, null: false, default: "monthly" # monthly | yearly
    end

    change_table :billing_invoices, bulk: true do |t|
      t.string :kind, null: false, default: "subscription" # subscription | one_off
      t.string :interval, null: false, default: "monthly"
      t.integer :extra_branches, null: false, default: 0
      t.integer :extra_registers, null: false, default: 0
      t.string :description # one-off invoices: what was sold (setup, training, a hardware kit)
    end
  end
end
