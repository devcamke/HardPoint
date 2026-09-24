class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :account, null: false, index: false
      t.references :creator, index: true
      t.references :eventable, polymorphic: true, null: false
      t.string :action, null: false
      t.jsonb :particulars, null: false, default: {}

      t.datetime :created_at, null: false
    end
    add_foreign_key :events, :accounts, deferrable: :immediate
    add_foreign_key :events, :users, column: :creator_id, deferrable: :immediate
    add_index :events, %i[ account_id created_at ]

    enable_row_level_security :events
  end
end
