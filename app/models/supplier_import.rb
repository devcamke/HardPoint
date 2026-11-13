# Brings a shop's suppliers across from a spreadsheet, with what the shop owed each one on the day (see
# SpreadsheetImport for how a file is checked and saved). A line whose name matches a supplier already here
# updates that supplier, in the columns the line fills in; other lines add suppliers.
#
# A balance becomes an invoice with nothing behind it, numbered OPENING BALANCE and dated balance_date
# (SupplierInvoice#opening_balance), which payments then settle like any other. It's in the supplier's own
# currency. It's only ever set for a supplier with no orders, invoices or payments yet, so importing the same
# file twice can't double what the shop owes; lines passed over for that are listed.
class SupplierImport
  include SpreadsheetImport

  COLUMNS = %w[ name contact_name phone email kra_pin address payment_terms_days balance balance_date notes ].freeze
  ATTRIBUTES = { "contact_name" => :contact_name, "phone" => :phone, "email" => :email, "kra_pin" => :tax_pin, "address" => :address, "notes" => :notes }.freeze
  OPENING_NUMBER = "OPENING BALANCE"

  Row = Data.define(:line, :supplier, :balance_cents, :balance_date)

  private
    def imported_event = "suppliers_imported"

    def build_rows
      @by_name = account.suppliers.index_by { _1.name.squish.downcase }
      seen = {}

      lines.filter_map do |data, line|
        messages = []
        name = data["name"].to_s.squish
        supplier = @by_name[name.downcase] || account.suppliers.new
        supplier.name = name
        ATTRIBUTES.each { |column, attribute| supplier[attribute] = data[column].to_s.strip if data[column].present? }
        if (days = days_for(data, messages))
          supplier.payment_terms_days = days
        end

        balance_cents, balance_date = balance_for(data, messages)
        messages << "balance is money the supplier owes you (#{data["balance"]}); leave it out and record it when you next pay them" if balance_cents&.negative?
        messages << "is the same supplier as line #{seen[name.downcase]}" if name.present? && seen[name.downcase]
        seen[name.downcase] ||= line
        messages.concat supplier.errors.full_messages unless supplier.valid?

        next problem(line, messages) && nil if messages.any?
        Row.new(line, supplier, balance_cents, balance_date)
      end
    end

    def import(row)
      supplier = row.supplier
      was_new, changed = supplier.new_record?, supplier.changed?
      trading = !was_new && supplier.trading?
      supplier.save!
      was_new ? @created_count += 1 : (@updated_count += 1 if changed)
      return unless row.balance_cents

      if trading
        pass_over row.line, "#{supplier.name} already has orders, invoices or payments, so the balance was left as it is"
      else
        supplier.supplier_invoices.create!(account: account, number: OPENING_NUMBER, opening_balance: true, invoice_date: row.balance_date,
          total_cents: row.balance_cents, tax_cents: 0, creator: creator, note: "Imported from #{filename.presence || "a spreadsheet"}")
        @balances_count += 1
        @balances_cents += supplier.to_base_cents(row.balance_cents)
      end
    end
end
