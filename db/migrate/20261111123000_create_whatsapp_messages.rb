class CreateWhatsappMessages < ActiveRecord::Migration[8.1]
  def change
    # Documents and reminders HardPoint sends on WhatsApp for a shop, through the WhatsApp Business Platform (or
    # recorded as simulated where it isn't set up), with what Meta says became of each: sent, delivered, read, failed.
    create_table :whatsapp_messages do |t|
      t.references :account, null: false, index: false
      t.references :document, polymorphic: true
      t.references :document_share
      t.references :sent_by
      t.string :template, null: false
      t.string :to_phone, null: false
      t.string :recipient_name
      t.string :status, null: false, default: "queued"
      t.string :provider_message_id
      t.string :error
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.timestamps
    end
    add_index :whatsapp_messages, %i[ account_id created_at ]
    # Meta's status updates name only its own message id, so they're matched by it alone.
    add_index :whatsapp_messages, :provider_message_id, unique: true, where: "provider_message_id IS NOT NULL"
    # The table is empty, so validating the keys locks nothing worth waiting for.
    safety_assured do
      add_foreign_key :whatsapp_messages, :accounts, deferrable: :immediate
      add_foreign_key :whatsapp_messages, :document_shares, deferrable: :immediate
    end
    enable_row_level_security :whatsapp_messages
  end
end
