class AddClientBillingToJobs < ActiveRecord::Migration[8.1]
  def change
    # Who the contractor works for, and what they add on top of the shop's prices when billing them.
    add_column :jobs, :client_name, :string
    add_column :jobs, :markup_percent, :decimal, precision: 5, scale: 2
  end
end
