class CreateAccountBackups < ActiveRecord::Migration[8.1]
  def change
    # A shop's own backups: taken on a schedule the owner chooses, or by an owner pressing "Back up now".
    create_table :account_backups do |t|
      t.references :account, null: false, index: false
      t.references :requested_by # nil for scheduled backups
      t.string :kind, null: false # manual | scheduled
      t.string :status, null: false, default: "queued" # queued | running | succeeded | failed | expired
      t.string :period # "daily:2026-11-07", "weekly:2026-W45", "monthly:2026-11": one scheduled backup per period
      t.integer :attempts, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :expires_at
      t.bigint :byte_size
      t.string :checksum # SHA-256 of the ZIP, checked again after it's stored
      t.jsonb :manifest, null: false, default: {} # rows per table, file count, schema version
      t.string :failure
      t.timestamps
    end
    add_index :account_backups, %i[ account_id created_at ]
    add_index :account_backups, %i[ account_id period ], unique: true, where: "period IS NOT NULL"
    add_index :account_backups, :status, where: "status IN ('queued', 'running')"

    add_foreign_key :account_backups, :accounts, deferrable: :immediate
    add_foreign_key :account_backups, :users, column: :requested_by_id, deferrable: :immediate
    enable_row_level_security :account_backups

    change_table :accounts, bulk: true do |t|
      t.string :backup_frequency, null: false, default: "daily" # off | daily | weekly | monthly
      t.integer :backups_kept, null: false, default: 7 # scheduled backups kept; manual ones are kept 30 days
      t.string :backup_notifications, null: false, default: "every" # every | failures
    end
  end
end
