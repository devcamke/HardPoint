class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    # A contractor's job or project (a house, a block of flats, a borehole): what they buy for it is
    # tagged to it, so they can see what it has cost and charge their own client.
    create_table :jobs do |t|
      t.references :account, null: false
      t.references :customer, null: false, index: false
      t.references :creator
      t.string :name, null: false
      t.string :site
      t.string :reference
      t.bigint :budget_cents
      t.string :status, null: false, default: "open"
      t.string :note
      t.datetime :closed_at
      t.timestamps
    end
    add_index :jobs, %i[ customer_id name ], unique: true
    add_index :jobs, %i[ account_id status ]

    add_reference :sales, :job, index: true
    add_reference :customer_orders, :job, index: true

    add_foreign_key :jobs, :accounts, deferrable: :immediate
    add_foreign_key :jobs, :customers, deferrable: :immediate
    add_foreign_key :jobs, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :sales, :jobs, deferrable: :immediate
    add_foreign_key :customer_orders, :jobs, deferrable: :immediate
    enable_row_level_security :jobs
  end
end
