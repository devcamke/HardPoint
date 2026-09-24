class CreateApiAndWebhooks < ActiveRecord::Migration[8.1]
  def change
    # A shop's keys to the public API. Only a SHA-256 digest of each token is kept; the prefix
    # ("hp_4f9k2…") identifies it in lists.
    create_table :api_keys do |t|
      t.references :account, null: false, index: false
      t.references :creator
      t.string :name, null: false
      t.string :token_digest, null: false, index: { unique: true }
      t.string :token_prefix, null: false
      t.string :scope, null: false, default: "read"
      t.datetime :last_used_at
      t.string :last_used_ip
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :api_keys, %i[ account_id revoked_at ]

    # The answer to a create request, kept for a day under the client's Idempotency-Key, so a
    # retried request gets the same answer instead of making a second order.
    create_table :api_idempotency_keys do |t|
      t.references :account, null: false, index: false
      t.references :api_key, null: false, index: false
      t.string :key, null: false
      t.string :request_digest, null: false
      t.integer :response_status, null: false
      t.jsonb :response_body, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :api_idempotency_keys, %i[ api_key_id key ], unique: true
    add_index :api_idempotency_keys, :account_id
    add_index :api_idempotency_keys, :created_at

    create_table :webhook_endpoints do |t|
      t.references :account, null: false, index: false
      t.references :creator
      t.string :url, null: false
      t.string :description
      t.text :secret, null: false
      t.jsonb :event_types, null: false, default: []
      t.boolean :active, null: false, default: true
      t.integer :failure_count, null: false, default: 0
      t.datetime :disabled_at
      t.string :disabled_reason
      t.timestamps
    end
    add_index :webhook_endpoints, %i[ account_id active ]

    # One event sent (or being sent) to one endpoint.
    create_table :webhook_deliveries do |t|
      t.references :account, null: false, index: false
      t.references :endpoint, null: false
      t.string :event, null: false
      t.uuid :event_id, null: false
      t.jsonb :payload, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.integer :response_status
      t.string :response_body
      t.string :last_error
      t.datetime :next_attempt_at
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :webhook_deliveries, %i[ status next_attempt_at ]
    add_index :webhook_deliveries, %i[ account_id created_at ]

    {
      api_keys: %i[ accounts ],
      api_idempotency_keys: %i[ accounts api_keys ],
      webhook_endpoints: %i[ accounts ],
      webhook_deliveries: %i[ accounts ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :api_keys, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :webhook_endpoints, :users, column: :creator_id, deferrable: :immediate
    add_foreign_key :webhook_deliveries, :webhook_endpoints, column: :endpoint_id, deferrable: :immediate
  end
end
