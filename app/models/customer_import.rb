# Brings a shop's customers across from a spreadsheet, with what each one owed on the day: the debtors' book a
# shop had before HardPoint (see SpreadsheetImport for how a file is checked and saved). A line whose phone
# number (or, with no phone, whose name) matches a customer already here updates that customer, in the columns
# the line fills in; other lines add customers.
#
# A balance becomes the customer's opening balance (CustomerPayment, kind "opening_balance"): one debt, dated
# balance_date, that payments then settle like any other; a negative balance is credit the customer had with
# the shop. It's only ever set on an account with nothing on it yet, so importing the same file twice can't
# double what anyone owes; lines passed over for that are listed.
class CustomerImport
  include SpreadsheetImport

  COLUMNS = %w[ name phone email kra_pin address credit_limit payment_terms_days balance balance_date notes ].freeze
  ATTRIBUTES = { "phone" => :phone, "email" => :email, "kra_pin" => :tax_pin, "address" => :address, "notes" => :notes }.freeze

  Row = Data.define(:line, :customer, :balance_cents, :balance_date)

  private
    def imported_event = "customers_imported"

    def build_rows
      @by_phone = account.customers.where.not(phone: [ nil, "" ]).group_by { last_nine(_1.phone) }
      @by_name = account.customers.group_by { _1.name.squish.downcase }
      seen = {}

      lines.filter_map do |data, line|
        messages = []
        customer = customer_for(data, messages)
        balance_cents, balance_date = balance_for(data, messages)
        key = last_nine(data["phone"]).presence || data["name"].to_s.squish.downcase
        messages << "is the same customer as line #{seen[key]}" if key.present? && seen[key]
        seen[key] ||= line
        messages.concat customer.errors.full_messages unless customer.valid?

        next problem(line, messages) && nil if messages.any?
        Row.new(line, customer, balance_cents, balance_date)
      end
    end

    # The customer this line is about, with the line's columns put on it: one already here, or a new one.
    def customer_for(data, messages)
      name = data["name"].to_s.squish
      customer = existing(name, data["phone"], messages) || account.customers.new
      customer.name = name
      ATTRIBUTES.each { |column, attribute| customer[attribute] = data[column].to_s.strip if data[column].present? }

      if data["credit_limit"].present?
        cents = Monetary.to_cents(clean_number(data["credit_limit"]))
        cents && cents >= 0 ? customer.credit_limit_cents = cents : messages << "credit_limit “#{data["credit_limit"]}” isn't an amount"
      end
      if (days = days_for(data, messages))
        customer.payment_terms_days = days
      end
      customer
    end

    def existing(name, phone, messages)
      digits = last_nine(phone)
      matches = digits.present? ? @by_phone[digits].to_a : @by_name[name.downcase].to_a
      messages << "matches #{matches.size} customers already here (#{matches.map(&:name).uniq.to_sentence}); give the line a phone number only one of them has" if matches.many?
      matches.first if matches.one?
    end

    def import(row)
      customer = row.customer
      was_new, changed = customer.new_record?, customer.changed?
      customer.save!
      was_new ? @created_count += 1 : (@updated_count += 1 if changed)
      return unless row.balance_cents

      if customer.customer_payments.exists? || customer.charged_cents.positive?
        pass_over row.line, "#{customer.name} already has entries on their account, so the balance was left as it is"
      else
        # What they owe is a charge, kept negative like a refund; credit they had with the shop is positive.
        customer.customer_payments.create!(account: account, kind: "opening_balance", amount_cents: -row.balance_cents, paid_on: row.balance_date,
          creator: creator, note: "Imported from #{filename.presence || "a spreadsheet"}")
        @balances_count += 1
        @balances_cents += row.balance_cents
      end
    end
end
