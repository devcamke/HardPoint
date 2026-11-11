class AddShelfLabelQueueToProducts < ActiveRecord::Migration[8.1]
  # The shelf-label queue. A product whose price or name changes (edited, a bulk price change, an import), or that
  # is new, waits for a new shelf label: label_due_at says since when, and label_old_price_cents keeps the price the
  # label on the shelf still shows. A trigger does it, so imports' upserts, which skip model callbacks, queue too.
  # Printing the labels clears both. Existing products start with nothing queued.
  disable_ddl_transaction!

  def up
    add_column :products, :label_due_at, :datetime
    add_column :products, :label_old_price_cents, :bigint
    add_index :products, %i[ account_id label_due_at ], where: "label_due_at IS NOT NULL", algorithm: :concurrently

    safety_assured do
      execute <<~SQL
        CREATE FUNCTION queue_shelf_label() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          IF TG_OP = 'INSERT' THEN
            NEW.label_due_at := COALESCE(NEW.label_due_at, now());
          ELSIF NEW.price_cents IS DISTINCT FROM OLD.price_cents OR NEW.name IS DISTINCT FROM OLD.name THEN
            -- The shelf shows the price from before the first change since the last label.
            IF OLD.label_due_at IS NULL THEN
              NEW.label_old_price_cents := OLD.price_cents;
            END IF;
            NEW.label_due_at := now();
          END IF;
          RETURN NEW;
        END
        $$;

        CREATE TRIGGER shelf_label_due BEFORE INSERT OR UPDATE OF price_cents, name ON products
          FOR EACH ROW EXECUTE FUNCTION queue_shelf_label();
      SQL
    end
  end

  def down
    safety_assured do
      execute "DROP TRIGGER shelf_label_due ON products; DROP FUNCTION queue_shelf_label();"
    end
    remove_index :products, %i[ account_id label_due_at ], algorithm: :concurrently
    remove_column :products, :label_old_price_cents
    remove_column :products, :label_due_at
  end
end
