class CreateSearchTerms < ActiveRecord::Migration[8.1]
  # The words of each product's name and SKU, and each customer's name and phone, one row each, for search.
  #
  # Under forced row-level security Postgres only uses an index for conditions it knows can't leak rows from other
  # shops ("leakproof"). ILIKE and trigram similarity aren't, so the trigram indexes went unused and every search read
  # the shop's whole catalogue. Comparing text (>=, <) is leakproof, so a word typed at the till is found here as a
  # range of the btree index: "cem" is every term from "cem" up to "cem" followed by the highest character.
  #
  # Triggers keep the terms in step with every write, including imports' upserts, which skip model callbacks.
  def up
    create_table :search_terms, id: false do |t|
      t.bigint :account_id, null: false
      t.string :record_type, null: false
      t.bigint :record_id, null: false
      t.text :term, null: false, collation: "C" # byte order, so a prefix is one contiguous range
    end
    # record_id carried in the index so a lookup never visits the table.
    add_index :search_terms, %i[ account_id record_type term ], include: :record_id, name: "index_search_terms_for_lookup"
    add_index :search_terms, %i[ record_type record_id ]
    enable_row_level_security :search_terms

    safety_assured do
      execute <<~SQL
        -- Lowercased words, split on spaces ("1/2" stays whole) and again on anything not a letter or digit
        -- ("CEM-50" also gives "cem" and "50"), each at most 100 characters.
        CREATE FUNCTION search_terms_for(words text) RETURNS SETOF text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
          SELECT DISTINCT left(term, 100) FROM (
            SELECT regexp_split_to_table(lower(words), '\\s+') AS term
            UNION ALL
            SELECT regexp_split_to_table(lower(words), '[^[:alnum:]]+')
          ) split WHERE term <> ''
        $$;

        -- A phone number's last nine digits (0722 000 111 and +254 722 000 111 are both 722000111).
        CREATE FUNCTION search_phone_term(phone text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
          SELECT CASE WHEN length(digits) >= 9 THEN right(digits, 9) END
          FROM (SELECT regexp_replace(coalesce(phone, ''), '\\D', '', 'g') AS digits) cleaned
        $$;

        CREATE FUNCTION refresh_search_terms() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
          IF TG_OP <> 'INSERT' THEN
            DELETE FROM search_terms WHERE record_type = TG_TABLE_NAME AND record_id = OLD.id;
          END IF;
          IF TG_OP <> 'DELETE' THEN
            IF TG_TABLE_NAME = 'products' THEN
              INSERT INTO search_terms (account_id, record_type, record_id, term)
                SELECT NEW.account_id, 'products', NEW.id, term FROM search_terms_for(NEW.name || ' ' || NEW.sku) term;
            ELSE
              INSERT INTO search_terms (account_id, record_type, record_id, term)
                SELECT NEW.account_id, 'customers', NEW.id, term FROM search_terms_for(NEW.name) term
                UNION SELECT NEW.account_id, 'customers', NEW.id, search_phone_term(NEW.phone) WHERE search_phone_term(NEW.phone) IS NOT NULL;
            END IF;
          END IF;
          RETURN NULL;
        END
        $$;

        CREATE TRIGGER search_terms_written AFTER INSERT OR DELETE ON products
          FOR EACH ROW EXECUTE FUNCTION refresh_search_terms();
        CREATE TRIGGER search_terms_changed AFTER UPDATE OF name, sku ON products
          FOR EACH ROW WHEN (OLD.name IS DISTINCT FROM NEW.name OR OLD.sku IS DISTINCT FROM NEW.sku)
          EXECUTE FUNCTION refresh_search_terms();
        CREATE TRIGGER search_terms_written AFTER INSERT OR DELETE ON customers
          FOR EACH ROW EXECUTE FUNCTION refresh_search_terms();
        CREATE TRIGGER search_terms_changed AFTER UPDATE OF name, phone ON customers
          FOR EACH ROW WHEN (OLD.name IS DISTINCT FROM NEW.name OR OLD.phone IS DISTINCT FROM NEW.phone)
          EXECUTE FUNCTION refresh_search_terms();

        -- Every shop's existing products and customers.
        SELECT set_config('app.bypass_rls', 'on', true);
        INSERT INTO search_terms (account_id, record_type, record_id, term)
          SELECT products.account_id, 'products', products.id, term
          FROM products, search_terms_for(products.name || ' ' || products.sku) term;
        INSERT INTO search_terms (account_id, record_type, record_id, term)
          SELECT customers.account_id, 'customers', customers.id, term
          FROM customers, search_terms_for(customers.name) term
          UNION SELECT account_id, 'customers', id, search_phone_term(phone) FROM customers WHERE search_phone_term(phone) IS NOT NULL;
        SELECT set_config('app.bypass_rls', 'off', true);
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL
        DROP TRIGGER search_terms_written ON products;
        DROP TRIGGER search_terms_changed ON products;
        DROP TRIGGER search_terms_written ON customers;
        DROP TRIGGER search_terms_changed ON customers;
        DROP FUNCTION refresh_search_terms();
        DROP FUNCTION search_phone_term(text);
        DROP FUNCTION search_terms_for(text);
      SQL
    end
    drop_table :search_terms
  end
end
