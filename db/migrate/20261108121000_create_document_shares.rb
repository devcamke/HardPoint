class CreateDocumentShares < ActiveRecord::Migration[8.1]
  def change
    # A link to one document sent by WhatsApp. A row per link, so a link can be revoked and a statement stays
    # fixed to the period it was sent with (before, links were signed tokens nobody could take back).
    create_table :document_shares do |t|
      t.references :account, null: false, index: false, foreign_key: { deferrable: :immediate }
      t.references :document, polymorphic: true, null: false, index: false
      t.references :created_by, null: false, foreign_key: { to_table: :users, deferrable: :immediate }
      t.string :token, null: false
      t.date :period_from # statements only
      t.date :period_to
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.integer :opened_count, null: false, default: 0
      t.datetime :last_opened_at
      t.timestamps
    end
    add_index :document_shares, :token, unique: true
    add_index :document_shares, %i[ account_id document_type document_id ]
    enable_row_level_security :document_shares
  end
end
