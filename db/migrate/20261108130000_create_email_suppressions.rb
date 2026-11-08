class CreateEmailSuppressions < ActiveRecord::Migration[8.1]
  def change
    # Addresses HardPoint must not email again, as SES reports them: a permanent bounce or a spam complaint.
    # Platform-wide (no account_id): the same mailbox is the same mailbox whichever shop typed it.
    create_table :email_suppressions do |t|
      t.string :email, null: false
      t.string :reason, null: false # bounce | complaint | manual
      t.string :detail # the bounce subtype and diagnostic, or the complaint feedback type
      t.integer :count, null: false, default: 0 # how many times SES has reported this address
      t.datetime :event_at, null: false
      t.timestamps
    end
    add_index :email_suppressions, :email, unique: true
  end
end
