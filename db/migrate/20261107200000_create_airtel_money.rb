class CreateAirtelMoney < ActiveRecord::Migration[8.1]
  def change
    # A shop's Airtel Money merchant account on Airtel Africa's Open API, with its credentials kept encrypted.
    # A branch can have its own; one without a branch serves every branch that doesn't.
    create_table :airtel_merchants do |t|
      t.references :account, null: false, index: false
      t.references :branch
      t.string :name, null: false
      t.string :environment, null: false, default: "sandbox"
      t.string :merchant_number # the Airtel Money till customers can pay to by hand, shown at the till
      t.text :client_id
      t.text :client_secret
      t.string :callback_token, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :airtel_merchants, :account_id
    add_index :airtel_merchants, :callback_token, unique: true

    # A "pay with Airtel Money" prompt sent to a customer's phone from the till.
    create_table :airtel_requests do |t|
      t.references :account, null: false, index: false
      t.references :merchant, null: false, index: false
      t.references :sale, null: false
      t.references :payment
      t.references :requested_by
      t.string :phone, null: false
      t.bigint :amount_cents, null: false
      t.string :transaction_id, null: false # ours, sent to Airtel and echoed in its callback
      t.string :status, null: false, default: "pending"
      t.string :airtel_money_id # Airtel's receipt for the payment
      t.string :result_code
      t.string :result_description
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :airtel_requests, %i[ account_id created_at ]
    add_index :airtel_requests, %i[ merchant_id transaction_id ], unique: true

    add_foreign_key :airtel_merchants, :accounts, deferrable: :immediate
    add_foreign_key :airtel_merchants, :branches, deferrable: :immediate
    add_foreign_key :airtel_requests, :accounts, deferrable: :immediate
    add_foreign_key :airtel_requests, :airtel_merchants, column: :merchant_id, deferrable: :immediate
    add_foreign_key :airtel_requests, :sales, deferrable: :immediate
    add_foreign_key :airtel_requests, :payments, deferrable: :immediate
    add_foreign_key :airtel_requests, :users, column: :requested_by_id, deferrable: :immediate
    enable_row_level_security :airtel_merchants
    enable_row_level_security :airtel_requests
  end
end
