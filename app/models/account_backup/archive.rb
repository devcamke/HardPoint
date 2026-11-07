# A backup's ZIP: the same files as an export (every table the shop owns as CSV, staff, settings,
# product images and delivery photos), read from one consistent snapshot of the database, plus a
# manifest.json listing every file's SHA-256 and every table's row count, so a copy can be checked
# long after it was made.
class AccountBackup::Archive < AccountExport::Archive
  FORMAT_VERSION = 1
  MANIFEST = "manifest.json".freeze

  # Writes the ZIP and returns its manifest.
  def write(path)
    snapshot { super }
    manifest
  end

  def manifest
    @manifest ||= {
      "format_version" => FORMAT_VERSION,
      "shop" => { "id" => @account.id, "name" => @account.name, "subdomain" => @account.subdomain },
      "created_at" => Time.current.utc.iso8601,
      "schema_version" => ActiveRecord::Base.connection_pool.migration_context.current_version.to_s,
      "tables" => row_counts.sort.to_h,
      "files" => checksums.transform_values(&:hexdigest).sort.to_h
    }
  end

  private
    # Reads every table as of one moment, so a sale and its lines (written while the backup runs)
    # are either both in it or both not. Tests already run inside a transaction, which is enough.
    def snapshot(&block)
      return yield if @connection.transaction_open?

      ApplicationRecord.transaction(isolation: :repeatable_read, &block)
    end

    def finish(zip)
      verify_row_counts!
      zip.put_next_entry MANIFEST
      zip.write JSON.pretty_generate(manifest)
    end

    # COPY's rows are counted as they're written; Postgres counts them again in the same snapshot.
    def verify_row_counts!
      row_counts.each do |table, rows|
        counted = @connection.select_value("SELECT count(*) FROM #{@connection.quote_table_name(table)} WHERE account_id = #{Integer(@account.id)}")
        raise AccountBackup::VerificationFailed, "#{table}: wrote #{rows} rows but the shop has #{counted}" unless counted == rows
      end
    end

    def readme
      super + <<~TEXT

        This is a backup. manifest.json lists every file in it with its SHA-256 checksum, and how
        many rows each table had, so you can check the copy is complete (sha256sum on Linux and
        macOS, Get-FileHash in Windows PowerShell).
      TEXT
    end
end
