class CreateSaasLayer < ActiveRecord::Migration[8.1]
  def change
    change_table :accounts do |t|
      t.string :plan, null: false, default: "business"
      t.string :subscription_status, null: false, default: "trialing"
      t.datetime :trial_ends_at
      t.datetime :current_period_ends_at
      t.datetime :trial_reminder_sent_at
      t.string :suspended_reason
      t.datetime :onboarding_completed_at
      t.datetime :taxes_confirmed_at
      t.datetime :test_receipt_printed_at
      t.datetime :deletion_scheduled_for
      t.references :deletion_requested_by
    end
    add_index :accounts, :subscription_status

    # What HardPoint bills a shop, one invoice per month. Numbers come from one platform-wide
    # sequence, since invoices from every shop share a series.
    create_table :billing_invoices do |t|
      t.references :account, null: false, index: false
      t.string :number, null: false, index: { unique: true }
      t.string :plan, null: false
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.bigint :amount_cents, null: false
      t.string :currency, null: false, default: "KES"
      t.string :status, null: false, default: "open"
      t.date :due_on, null: false
      t.datetime :paid_at
      t.datetime :reminded_at
      t.timestamps
    end
    add_index :billing_invoices, %i[ account_id status ]

    create_table :billing_payments do |t|
      t.references :account, null: false, index: false
      t.references :invoice, null: false
      t.references :user
      t.string :provider, null: false
      t.string :status, null: false, default: "pending"
      t.bigint :amount_cents, null: false
      t.string :reference, null: false, index: { unique: true }
      t.string :receipt
      t.string :phone
      t.string :failure
      t.datetime :completed_at
      t.timestamps
    end

    # Messages from the platform to every shop (maintenance, new features). Not any one shop's data.
    create_table :announcements do |t|
      t.string :title, null: false
      t.text :body
      t.string :level, null: false, default: "info"
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.timestamps
    end

    create_table :support_requests do |t|
      t.references :account, null: false, index: false
      t.references :user, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.string :page
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :support_requests, %i[ account_id created_at ]

    # A full export of a shop's data: a ZIP of CSVs and files, kept for a week.
    create_table :account_exports do |t|
      t.references :account, null: false, index: false
      t.references :requested_by, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at
      t.string :failure
      t.timestamps
    end
    add_index :account_exports, %i[ account_id created_at ]

    # The platform's record that a shop was deleted (the shop's own data is gone): who, when, and
    # what it had been billed, which the platform keeps for its own tax records.
    create_table :account_deletions do |t|
      t.bigint :former_account_id, null: false
      t.string :name, null: false
      t.string :subdomain, null: false
      t.string :requested_by_email
      t.jsonb :billing_invoices, null: false, default: []
      t.datetime :requested_at
      t.datetime :created_at, null: false
    end

    {
      billing_invoices: %i[ accounts ],
      billing_payments: %i[ accounts ],
      support_requests: %i[ accounts users ],
      account_exports: %i[ accounts ]
    }.each do |table, references|
      references.each { |referenced| add_foreign_key table, referenced, deferrable: :immediate }
      enable_row_level_security table
    end
    add_foreign_key :billing_payments, :billing_invoices, column: :invoice_id, deferrable: :immediate
    add_foreign_key :billing_payments, :users, deferrable: :immediate
    add_foreign_key :account_exports, :users, column: :requested_by_id, deferrable: :immediate
    add_foreign_key :accounts, :users, column: :deletion_requested_by_id, deferrable: :immediate

    reversible do |direction|
      direction.up do
        execute "CREATE SEQUENCE billing_invoice_numbers START 1"
        # Existing shops start a 30-day trial now.
        execute "UPDATE accounts SET trial_ends_at = NOW() + INTERVAL '30 days'"
      end
      direction.down { execute "DROP SEQUENCE IF EXISTS billing_invoice_numbers" }
    end
  end
end
