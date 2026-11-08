# Search under row-level security. Postgres won't use an index for a condition whose operator isn't "leakproof"
# (ILIKE, similarity) on a table with a row security policy, because the operator could leak rows the policy
# hides; so every search read the shop's whole catalogue. These functions do the matching with row security
# switched off and the shop's id as an explicit condition instead: they're SECURITY DEFINER, owned by the
# hardpoint_search role, which has BYPASSRLS and nothing else (no login; SELECT on these four tables only), so
# the trigram indexes apply, and each function can only ever return rows of the shop it was asked about.
#
# The role is created by the database's superuser (config/postgres/create_app_role.sh, the README's setup
# line, the CI workflow). Ownership isn't in db/structure.sql (pg_dump --no-owner), so SearchFunctions sets it
# again after every schema load (lib/tasks/search.rake, test/test_helper.rb).
class AddSearchFunctions < ActiveRecord::Migration[8.1]
  def up
    unless select_value("SELECT 1 FROM pg_roles WHERE rolname = '#{SearchFunctions::ROLE}'")
      raise "Create the search role first, as the database superuser:\n  #{SearchFunctions::CREATE_ROLE_SQL}"
    end

    safety_assured do
      execute <<~SQL
        CREATE OR REPLACE FUNCTION search_product_ids(shop bigint, patterns text[], barcode text)
        RETURNS SETOF bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
        DECLARE conditions text;
        BEGIN
          -- Every pattern must match the name or the SKU; patterns arrive LIKE-escaped and wrapped in %.
          SELECT string_agg(format('(p.name ILIKE %L OR p.sku ILIKE %L)', w, w), ' AND ') INTO conditions FROM unnest(patterns) AS w;
          RETURN QUERY EXECUTE format(
            'SELECT p.id FROM products p WHERE p.account_id = $1 AND (%s)
             UNION SELECT b.product_id FROM barcodes b WHERE b.account_id = $1 AND b.code = $2',
            coalesce(conditions, 'false')) USING shop, barcode;
        END $$;

        -- In SQL functions a column wins over a parameter of the same name, so the parameters are named apart.
        CREATE OR REPLACE FUNCTION search_customer_ids(shop bigint, name_pattern text, phone_pattern text)
        RETURNS SETOF bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
          SELECT c.id FROM customers c WHERE c.account_id = shop AND (c.name ILIKE name_pattern OR (phone_pattern IS NOT NULL AND c.phone LIKE phone_pattern))
        $$;

        CREATE OR REPLACE FUNCTION search_supplier_ids(shop bigint, name_pattern text)
        RETURNS SETOF bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
          SELECT s.id FROM suppliers s WHERE s.account_id = shop AND s.name ILIKE name_pattern
        $$;
      SQL
    end

    SearchFunctions.ensure_privileges!(connection)
  end

  def down
    safety_assured do
      execute "DROP FUNCTION IF EXISTS search_product_ids(bigint, text[], text), search_customer_ids(bigint, text, text), search_supplier_ids(bigint, text)"
    end
  end
end
