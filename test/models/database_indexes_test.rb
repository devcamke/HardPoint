require "test_helper"

class DatabaseIndexesTest < ActiveSupport::TestCase
  test "every foreign key has an index led by its column" do
    unindexed = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT c.conrelid::regclass::text || '.' || a.attname
      FROM pg_constraint c
      JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
      WHERE c.contype = 'f' AND array_length(c.conkey, 1) = 1
        AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])
      ORDER BY 1
    SQL

    assert_empty unindexed, "Add an index for these foreign keys (deletes and account-wide queries scan without one)"
  end

  test "no two indexes on a table start with the same columns as each other (duplicates only slow writes)" do
    duplicates = ActiveRecord::Base.connection.select_rows(<<~SQL)
      SELECT a.indrelid::regclass::text, a.indexrelid::regclass::text, b.indexrelid::regclass::text
      FROM pg_index a JOIN pg_index b ON a.indrelid = b.indrelid AND a.indexrelid < b.indexrelid
      WHERE a.indkey::text = b.indkey::text AND a.indpred IS NULL AND b.indpred IS NULL
        AND a.indexprs IS NULL AND b.indexprs IS NULL AND a.indisunique = b.indisunique
    SQL

    assert_empty duplicates, "Identical indexes: #{duplicates.map { _1.join(" ") }.join("; ")}"
  end
end
