class CreateDeliveryNoteLines < ActiveRecord::Migration[8.1]
  def change
    # What each delivery note carries: a quantity of each sale line, so a sale can go out in parts (the cement
    # today, the roofing sheets when they're in) and each note prints only what's on the lorry.
    create_table :delivery_note_lines do |t|
      t.references :account, null: false
      t.references :delivery_note, null: false
      t.references :sale_line, null: false
      t.decimal :quantity, precision: 14, scale: 3, null: false
      t.timestamps
    end
    # The table is empty, so validating the keys locks nothing worth waiting for.
    safety_assured do
      add_foreign_key :delivery_note_lines, :accounts, deferrable: :immediate
      add_foreign_key :delivery_note_lines, :delivery_notes, deferrable: :immediate
      add_foreign_key :delivery_note_lines, :sale_lines, deferrable: :immediate
    end
    enable_row_level_security :delivery_note_lines

    up_only do
      # Notes made before this carried the whole sale. Row-level security applies to the migration's role too.
      safety_assured do
        transaction do
          execute <<~SQL
            SET LOCAL app.bypass_rls = 'on';
            INSERT INTO delivery_note_lines (account_id, delivery_note_id, sale_line_id, quantity, created_at, updated_at)
            SELECT delivery_notes.account_id, delivery_notes.id, sale_lines.id, sale_lines.quantity, delivery_notes.created_at, delivery_notes.created_at
              FROM delivery_notes JOIN sale_lines ON sale_lines.sale_id = delivery_notes.sale_id
          SQL
        end
      end
    end
  end
end
