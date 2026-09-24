class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :subdomain, null: false, index: { unique: true }
      t.string :time_zone, null: false, default: "Nairobi"
      t.string :currency, null: false, default: "KES"

      t.timestamps
    end
  end
end
