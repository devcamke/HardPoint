require "csv"

# Writes the ZIP: every table that belongs to the shop as a CSV (secrets left out), the staff list,
# the shop's settings, attached files, and a README explaining the format.
class AccountExport::Archive
  # Internal bookkeeping, and sign-in sessions (security data, not the shop's records).
  SKIPPED_TABLES = %w[ account_exports document_sequences etims_item_registrations product_imports sessions ].freeze
  # Credentials and hashes never leave the database.
  SECRET_COLUMNS = /digest|secret|token|passkey|consumer_key|cmc_key|failed_pin_attempts/

  def initialize(account)
    @account = account
    @connection = ActiveRecord::Base.connection
  end

  def write(path)
    Zip::OutputStream.open(path) do |zip|
      add zip, "README.txt", readme
      add zip, "shop.csv", shop_csv
      add zip, "staff.csv", staff_csv
      tables.each { |table| copy_table zip, table }
      add_files zip
    end
  end

  def tables
    @tables ||= @connection.select_values(<<~SQL) - SKIPPED_TABLES
      SELECT table_name FROM information_schema.columns
      WHERE column_name = 'account_id' AND table_schema = current_schema() ORDER BY table_name
    SQL
  end

  private
    def add(zip, name, content)
      zip.put_next_entry name
      zip.write content
    end

    # Streams the table straight from Postgres with COPY; row-level security still applies.
    def copy_table(zip, table)
      columns = @connection.columns(table).map(&:name).grep_v(SECRET_COLUMNS).map { @connection.quote_column_name(_1) }
      order = @connection.columns(table).any? { _1.name == "id" } ? " ORDER BY id" : ""
      sql = "SELECT #{columns.join(", ")} FROM #{@connection.quote_table_name(table)} WHERE account_id = #{Integer(@account.id)}#{order}"

      zip.put_next_entry "data/#{table}.csv"
      raw = @connection.raw_connection
      raw.copy_data("COPY (#{sql}) TO STDOUT WITH (FORMAT csv, HEADER true)") do
        while (row = raw.get_copy_data)
          zip.write row
        end
      end
    end

    def shop_csv
      attributes = @account.attributes.slice(*%w[ id name subdomain time_zone currency plan subscription_status trial_ends_at
        current_period_ends_at receipt_footer max_cashier_discount_percent sms_enabled created_at ])
      CSV.generate { |csv| csv << attributes.keys << attributes.values }
    end

    def staff_csv
      CSV.generate do |csv|
        csv << %w[ membership_id name email_address role joined_at ]
        @account.memberships.includes(:user).order(:id).each do |membership|
          csv << [ membership.id, membership.user.name, membership.user.email_address, membership.role, membership.created_at ]
        end
      end
    end

    def add_files(zip)
      @account.products.joins(:image_attachment).includes(image_attachment: :blob).find_each do |product|
        add_attachment zip, "files/products/#{product.id}-#{product.sku.parameterize}", product.image
      end
      @account.delivery_notes.joins(:proof_photo_attachment).includes(proof_photo_attachment: :blob).find_each do |note|
        add_attachment zip, "files/delivery_notes/#{note.id}", note.proof_photo
      end
    end

    def add_attachment(zip, stem, attachment)
      zip.put_next_entry "#{stem}#{File.extname(attachment.filename.to_s)}"
      attachment.download { |chunk| zip.write chunk }
    end

    def readme
      <<~TEXT
        HardPoint export for #{@account.name} (#{@account.subdomain})
        Made #{Time.current.in_time_zone(@account.time_zone).to_fs(:long)} (#{@account.time_zone})

        shop.csv          The shop's settings and plan.
        staff.csv         Everyone with access, their email address and role.
        data/*.csv        One file per kind of record, e.g. products.csv, sales.csv, sale_lines.csv,
                          customers.csv, stock_movements.csv. The first row names the columns.
        files/            Product images and delivery photos, named by the record's id.

        How to read the files
        - Columns ending in _id refer to the id column of another file: sale_lines.sale_id is sales.id.
        - Columns ending in _cents are amounts in cents: 125050 is #{@account.currency} 1,250.50.
        - Quantities are decimals: 2.500 is two and a half (metres, kilograms...).
        - Times are in UTC (Nairobi is UTC+3).
        - Passwords, PINs and API keys are not included.

        Files are UTF-8 CSV and open in Excel, LibreOffice or Google Sheets.
      TEXT
    end
end
