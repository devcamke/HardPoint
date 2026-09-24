class CreateIntegrations < ActiveRecord::Migration[8.1]
  def change
    # A shop's M-Pesa Paybill or Till number and its Daraja API credentials (encrypted).
    # Safaricom's callbacks find the shop by callback_token in the URL, never by the payload.
    create_table :mpesa_shortcodes do |t|
      t.references :account, null: false, index: false
      t.references :branch
      t.string :name, null: false
      t.string :environment, null: false, default: "sandbox"
      t.string :transaction_type, null: false, default: "paybill"
      t.string :shortcode, null: false
      t.string :till_number
      t.text :consumer_key
      t.text :consumer_secret
      t.text :passkey
      t.string :callback_token, null: false
      t.boolean :active, null: false, default: true
      t.datetime :c2b_registered_at
      t.timestamps
    end
    add_index :mpesa_shortcodes, :callback_token, unique: true
    add_index :mpesa_shortcodes, %i[ account_id shortcode ], unique: true

    # "Pay with M-Pesa" prompts sent to a customer's phone from the till (STK push).
    create_table :mpesa_stk_requests do |t|
      t.references :account, null: false, index: false
      t.references :shortcode, null: false
      t.references :sale, null: false
      t.references :payment
      t.references :requested_by
      t.string :phone, null: false
      t.bigint :amount_cents, null: false
      t.string :merchant_request_id
      t.string :checkout_request_id
      t.string :status, null: false, default: "pending"
      t.string :result_code
      t.string :result_description
      t.string :receipt_number
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :mpesa_stk_requests, :checkout_request_id, unique: true

    # Money Safaricom says arrived: confirmed STK payments and direct Paybill/Till payments (C2B),
    # and what each was matched to (a sale's payment, an order deposit, an account payment).
    create_table :mpesa_transactions do |t|
      t.references :account, null: false, index: false
      t.references :shortcode, null: false
      t.string :source, null: false
      t.string :trans_id, null: false
      t.bigint :amount_cents, null: false
      t.string :phone
      t.string :payer_name
      t.string :bill_reference
      t.datetime :transacted_at, null: false
      t.references :matched, polymorphic: true
      t.datetime :matched_at
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :mpesa_transactions, %i[ account_id trans_id ], unique: true
    add_index :mpesa_transactions, %i[ account_id transacted_at ]

    # KRA eTIMS (OSCU): one control unit per branch.
    create_table :etims_devices do |t|
      t.references :account, null: false, index: false
      t.references :branch, null: false, index: { unique: true }
      t.string :environment, null: false, default: "sandbox"
      t.string :tin, null: false
      t.string :bhf_id, null: false, default: "00"
      t.string :serial_number, null: false
      t.text :cmc_key
      t.string :sdc_id
      t.string :mrc_no
      t.string :default_item_class_code, null: false, default: "5020230500"
      t.boolean :active, null: false, default: true
      t.datetime :initialized_at
      t.timestamps
    end

    # Each sale, void and return sent (or waiting to be sent) to KRA, with what KRA signed.
    create_table :etims_submissions do |t|
      t.references :account, null: false, index: false
      t.references :device, null: false
      t.references :document, polymorphic: true, null: false, index: false
      t.string :kind, null: false
      t.integer :invoice_number, null: false
      t.integer :original_invoice_number
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.string :last_error
      t.datetime :last_attempted_at
      t.integer :receipt_number
      t.integer :total_receipt_number
      t.string :internal_data
      t.string :receipt_signature
      t.string :sdc_date_time
      t.datetime :sent_at
      t.timestamps
    end
    add_index :etims_submissions, %i[ document_type document_id kind ], unique: true
    add_index :etims_submissions, %i[ device_id invoice_number ], unique: true
    add_index :etims_submissions, %i[ account_id status ]

    # KRA registers items per branch (control unit), so each product is registered once per device.
    create_table :etims_item_registrations do |t|
      t.references :account, null: false, index: false
      t.references :device, null: false
      t.references :product, null: false
      t.datetime :created_at, null: false
    end
    add_index :etims_item_registrations, %i[ device_id product_id ], unique: true

    add_column :tax_rates, :etims_code, :string
    add_column :units, :etims_code, :string
    add_column :categories, :etims_class_code, :string

    add_column :accounts, :sms_enabled, :boolean, null: false, default: false

    create_table :sms_messages do |t|
      t.references :account, null: false, index: false
      t.references :source, polymorphic: true
      t.references :sender
      t.string :recipient, null: false
      t.text :body, null: false
      t.string :purpose, null: false
      t.string :status, null: false, default: "queued"
      t.string :provider_message_id
      t.string :cost
      t.string :error
      t.datetime :sent_at
      t.datetime :created_at, null: false
    end
    add_index :sms_messages, %i[ account_id created_at ]

    {
      mpesa_shortcodes: %i[ accounts branches ],
      mpesa_stk_requests: %i[ accounts sales payments ],
      mpesa_transactions: %i[ accounts ],
      etims_devices: %i[ accounts branches ],
      etims_submissions: %i[ accounts ],
      etims_item_registrations: %i[ accounts products ],
      sms_messages: %i[ accounts ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :mpesa_stk_requests, :mpesa_shortcodes, column: :shortcode_id, deferrable: :immediate
    add_foreign_key :mpesa_stk_requests, :users, column: :requested_by_id, deferrable: :immediate
    add_foreign_key :mpesa_transactions, :mpesa_shortcodes, column: :shortcode_id, deferrable: :immediate
    add_foreign_key :etims_submissions, :etims_devices, column: :device_id, deferrable: :immediate
    add_foreign_key :etims_item_registrations, :etims_devices, column: :device_id, deferrable: :immediate
    add_foreign_key :sms_messages, :users, column: :sender_id, deferrable: :immediate
  end
end
