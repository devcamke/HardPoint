# The SQL functions searches run through (db/migrate/*_add_search_functions.rb): SECURITY DEFINER, owned by a
# role that bypasses row-level security, so Postgres can use the trigram indexes. pg_dump leaves owners and
# grants out of db/structure.sql, so after any schema load (a fresh server, a test database) the functions
# belong to whoever loaded them and search still works, just without the indexes; ensure_privileges! puts
# the ownership back. Run by db:prepare, db:schema:load and db:test:prepare (lib/tasks/search.rake) and by
# the test workers as they start.
module SearchFunctions
  ROLE = "hardpoint_search"
  CREATE_ROLE_SQL = %(CREATE ROLE #{ROLE} NOLOGIN BYPASSRLS; GRANT #{ROLE} TO hardpoint;).freeze
  FUNCTIONS = [ "search_product_ids(bigint, text[], text)", "search_customer_ids(bigint, text, text)", "search_supplier_ids(bigint, text)" ].freeze
  TABLES = %w[ products barcodes customers suppliers ].freeze

  # True when the functions now belong to the bypassing role; false when the role doesn't exist here.
  def self.ensure_privileges!(connection = ActiveRecord::Base.connection)
    return false unless role_exists?(connection)
    return false unless FUNCTIONS.all? { function_exists?(_1, connection) }

    app_role = connection.quote_column_name(connection.select_value("SELECT current_user"))
    # A function's new owner must be allowed to create in its schema; the app role owns the database, so it may grant that.
    connection.execute "GRANT CREATE ON SCHEMA public TO #{ROLE}; GRANT SELECT ON #{TABLES.join(", ")} TO #{ROLE}"
    FUNCTIONS.each do |function|
      connection.execute <<~SQL
        ALTER FUNCTION #{function} OWNER TO #{ROLE};
        REVOKE ALL ON FUNCTION #{function} FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION #{function} TO #{app_role};
      SQL
    end
    true
  end

  # Whether searches are getting the indexes: every function is owned by the bypassing role.
  def self.bypassing_rls?(connection = ActiveRecord::Base.connection)
    owners = connection.select_values("SELECT DISTINCT proowner::regrole::text FROM pg_proc WHERE proname IN ('search_product_ids', 'search_customer_ids', 'search_supplier_ids')")
    owners == [ ROLE ]
  end

  def self.role_exists?(connection = ActiveRecord::Base.connection)
    connection.select_value("SELECT 1 FROM pg_roles WHERE rolname = '#{ROLE}'").present?
  end

  def self.function_exists?(signature, connection)
    connection.select_value("SELECT 1 FROM pg_proc WHERE oid = #{connection.quote(signature)}::regprocedure").present?
  rescue ActiveRecord::StatementInvalid
    false
  end
end
