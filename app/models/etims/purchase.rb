# An invoice a supplier issued to the shop's KRA PIN, as eTIMS holds it: who sold, what, how much and the VAT.
# The shop's control unit fetches them (Etims::Purchase.fetch); each one then waits to be dealt with:
#
#   receive         the goods go into stock (a goods received note) and the invoice goes on what the shop owes
#   record_invoice  the invoice alone, for goods already received or for services
#   dismiss         set aside: not this branch's, a duplicate, or something handled another way
#
# Nothing is typed twice: the supplier is found by KRA PIN (or added), each line is matched to a product by its
# barcode, by what the same supplier's line was matched to last time, by the supplier's own code for it, or by
# name. Lines that match nothing are pointed at a product by hand, or left out (transport, say).
class Etims::Purchase < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  STATUSES = %w[ new received invoiced dismissed ].freeze
  # The first time a control unit asks, how far back to look; after that, from the last time it asked.
  FIRST_LOOK_BACK = 60.days
  # Asked again from a little before the last answer, so nothing issued while KRA was answering is missed.
  OVERLAP = 1.day

  belongs_to :device
  belongs_to :supplier, optional: true
  belongs_to :goods_receipt, optional: true
  belongs_to :supplier_invoice, optional: true
  belongs_to :handled_by, class_name: "User", optional: true

  money_attribute :total, :tax

  validates :status, inclusion: { in: STATUSES }
  validates :supplier_tin, :invoice_number, :sales_date, presence: true
  validates_same_account :device, :supplier, :goods_receipt, :supplier_invoice

  scope :chronologically, -> { order(sales_date: :desc, id: :desc) }
  scope :waiting, -> { where(status: "new") }

  delegate :branch, to: :device

  # One line of the invoice. Costs are ex VAT, as HardPoint keeps them.
  Item = Data.define(:seq, :code, :name, :barcode, :quantity, :unit, :unit_cost_cents, :tax_cents, :total_cents, :tax_type, :product_id) do
    def value_cents = total_cents - tax_cents
  end

  class << self
    # Asks KRA for the invoices issued to this control unit's PIN since it last asked, and keeps the new ones.
    # Returns how many were new. KRA being unreachable or refusing is noted on the device, not raised.
    def fetch(device)
      since = device.purchases_checked_at ? device.purchases_checked_at - OVERLAP : FIRST_LOOK_BACK.ago
      asked_at = Time.current
      added = device.client.purchases(since: since).count { |invoice| keep(device, invoice) }
      device.update!(purchases_checked_at: asked_at, purchases_error: nil)
      added
    rescue Etims::Client::Refused, JsonHttp::Unreachable => error
      device.update!(purchases_error: error.message.first(250))
      0
    end

    private
      # True when the invoice wasn't here already.
      def keep(device, invoice)
        tin = invoice["spplrTin"].to_s.strip.upcase
        number = invoice["spplrInvcNo"].to_s.strip
        return false if tin.blank? || number.blank?

        purchase = find_or_initialize_by(device: device, supplier_tin: tin, supplier_bhf_id: invoice["spplrBhfId"].presence || "00",
          invoice_number: number, receipt_type: invoice["rcptTyCd"].presence || "S")
        return false if purchase.persisted?

        purchase.assign_attributes(account: device.account, supplier_name: invoice["spplrNm"].to_s.squish.presence, sales_date: parse_date(invoice["salesDt"] || invoice["cfmDt"]),
          total_cents: cents(invoice["totAmt"]), tax_cents: cents(invoice["totTaxAmt"]), items: Array(invoice["itemList"]).map { item_from(_1) })
        purchase.supplier = device.account.suppliers.find_by(tax_pin: tin)
        # Typed in by hand before KRA was asked: nothing more to do with it.
        if (recorded = purchase.supplier&.supplier_invoices&.find_by(number: number.upcase))
          purchase.assign_attributes(status: "invoiced", supplier_invoice: recorded, goods_receipt: recorded.goods_receipt, handled_at: Time.current, note: "Already recorded by hand")
        end
        purchase.save!
        true
      rescue ActiveRecord::RecordNotUnique
        false
      end

      def item_from(item)
        { "seq" => item["itemSeq"].to_i, "code" => item["itemCd"].to_s.strip.presence, "name" => item["itemNm"].to_s.squish, "barcode" => item["bcd"].to_s.strip.presence,
          "quantity" => item["qty"].to_d.to_s("F"), "unit" => item["qtyUnitCd"].to_s.presence, "tax_type" => item["taxTyCd"].to_s.presence,
          "tax_cents" => cents(item["taxAmt"]), "total_cents" => cents(item["totAmt"]) }
      end

      def cents(shillings) = (shillings.to_d * 100).round

      # KRA sends dates as 20261114 and times as 20261114093000 or "2026-11-14 09:30:00".
      def parse_date(value)
        Date.strptime(value.to_s.gsub(/\D/, "").first(8), "%Y%m%d")
      rescue Date::Error
        Date.current
      end
  end

  def new? = status == "new"
  def credit_note? = receipt_type == "R"

  def name
    "#{supplier_name || supplier_tin} #{invoice_number}"
  end

  def lines
    @lines ||= items.map do |item|
      quantity = item["quantity"].to_d
      value = item["total_cents"].to_i - item["tax_cents"].to_i
      Item.new(seq: item["seq"], code: item["code"], name: item["name"], barcode: item["barcode"], quantity: quantity, unit: item["unit"],
        unit_cost_cents: quantity.positive? ? (value / quantity).round : 0, tax_cents: item["tax_cents"].to_i, total_cents: item["total_cents"].to_i,
        tax_type: item["tax_type"], product_id: item["product_id"])
    end
  end

  # The product each line most likely is, by line number: { 1 => product, 2 => nil }.
  def suggested_products
    @suggested_products ||= begin
      remembered = remembered_products
      by_barcode = account.barcodes.where(code: lines.filter_map(&:barcode), product_unit_id: nil).includes(:product).to_h { [ _1.code, _1.product ] }
      by_supplier_code = supplier ? supplier.supplier_products.where(supplier_sku: lines.filter_map(&:code)).includes(:product).to_h { [ _1.supplier_sku, _1.product ] } : {}
      by_name = account.products.active.where("lower(name) IN (?)", lines.map { _1.name.downcase }).to_h { [ _1.name.downcase, _1 ] }

      lines.to_h do |line|
        [ line.seq, by_barcode[line.barcode] || remembered[line.code || line.name.downcase] || by_supplier_code[line.code] || by_name[line.name.downcase] ]
      end
    end
  end

  # Receives the goods at the control unit's branch and records the invoice against the delivery, in one go.
  # `choices` is by line number: { "1" => { product_code:, quantity:, unit_cost:, batch_number:, expires_on:, skip: } }.
  # A line with no choice goes to its suggested product; one that matches nothing has to be pointed at a product or skipped.
  def receive(choices = {}, by: Current.user)
    handle(by) do
      receipt_lines = lines.filter_map { |line| receipt_line(line, (choices[line.seq.to_s] || {}).to_h.symbolize_keys) }
      next if errors.any?
      next errors.add(:base, "Choose at least one line to receive, or record it as an invoice only") if receipt_lines.empty?

      receipt = account.goods_receipts.new(supplier: supplier!, branch: branch, supplier_reference: invoice_number, receiver: by,
        note: "From KRA eTIMS invoice #{invoice_number}", lines_attributes: receipt_lines.map { _1.except(:line) })
      next copy_errors(receipt) unless receipt.save

      remember(receipt_lines)
      invoice = record_supplier_invoice(receipt, by) or next
      update!(status: "received", goods_receipt: receipt, supplier_invoice: invoice, handled_by: by, handled_at: Time.current)
      track_event "received", supplier: supplier.name, total: total_cents, goods_receipt: receipt.reference
    end
  end

  # The invoice alone goes on what the shop owes: the goods came in already (against `goods_receipt`, if it's said
  # which delivery), or there were none (a service).
  def record_invoice(goods_receipt: nil, by: Current.user)
    handle(by) do
      invoice = record_supplier_invoice(goods_receipt, by) or next
      update!(status: "invoiced", goods_receipt: goods_receipt, supplier_invoice: invoice, handled_by: by, handled_at: Time.current)
      track_event "invoiced", supplier: supplier.name, total: total_cents
    end
  end

  def dismiss(reason: nil, by: Current.user)
    new? && update(status: "dismissed", note: reason.to_s.squish.first(200).presence, handled_by: by, handled_at: Time.current)
  end

  def restore
    status == "dismissed" && update(status: "new", note: nil, handled_by: nil, handled_at: nil)
  end

  private
    # Everything or nothing, and only once: two people pressing Receive get one delivery between them.
    def handle(by)
      errors.clear
      transaction do
        lock!
        if !new?
          errors.add :base, "This invoice has already been #{status}"
        elsif credit_note?
          errors.add :base, "This is a credit note. Record what went back as a return to the supplier"
        elsif supplier&.foreign?
          errors.add :base, "#{supplier.name} invoices in #{supplier.currency}, and KRA's figures are in #{account.currency}. Record this one by hand"
        else
          yield
        end
        raise ActiveRecord::Rollback if errors.any?
      end
      errors.none?
    end

    def receipt_line(line, choice)
      return if choice[:skip].present? && choice[:skip] != "0"

      product = choice[:product_code].present? ? account.products.find_by_code(choice[:product_code]) : suggested_products[line.seq]
      if product.nil?
        errors.add :base, choice[:product_code].present? ? "No product with barcode or SKU “#{choice[:product_code]}” (line #{line.seq}, #{line.name})" :
          "Say which product “#{line.name}” is (line #{line.seq}), or leave it out"
        return
      end

      { line: line, account: account, product: product, quantity: choice[:quantity].presence || line.quantity,
        unit_cost_cents: choice[:unit_cost].present? ? Monetary.to_cents(choice[:unit_cost]) : line.unit_cost_cents,
        batch_number: choice[:batch_number].presence, expires_on: choice[:expires_on].presence }
    end

    def record_supplier_invoice(goods_receipt, by)
      invoice = account.supplier_invoices.new(supplier: supplier!, goods_receipt: goods_receipt, number: invoice_number, invoice_date: sales_date,
        total_cents: total_cents, tax_cents: tax_cents, creator: by, note: "From KRA eTIMS")
      return invoice if invoice.save

      copy_errors(invoice)
      nil
    end

    # The supplier with this KRA PIN, added from KRA's details the first time they're bought from.
    def supplier!
      self.supplier ||= account.suppliers.find_by(tax_pin: supplier_tin) ||
        account.suppliers.create!(name: unused_supplier_name, tax_pin: supplier_tin)
    end

    def unused_supplier_name
      name = supplier_name.presence || "Supplier #{supplier_tin}"
      account.suppliers.exists?(name: name) ? "#{name} (#{supplier_tin})" : name
    end

    # Which product each line was, kept on the invoice so the same supplier's next one matches by itself.
    def remember(receipt_lines)
      chosen = receipt_lines.to_h { [ _1[:line].seq, _1[:product].id ] }
      update!(items: items.map { |item| item.merge("product_id" => chosen[item["seq"]]) })
      @lines = nil
    end

    # { the supplier's item code, or the item's name => product } from this supplier's invoices received before.
    def remembered_products
      earlier = account.etims_purchases.where(supplier_tin: supplier_tin, status: "received").where.not(id: id).order(handled_at: :desc).limit(50).pluck(:items).flatten
      ids = earlier.filter_map { _1["product_id"] }.uniq
      products = account.products.where(id: ids).index_by(&:id)
      earlier.reverse.each_with_object({}) do |item, found|
        product = products[item["product_id"]] or next
        found[item["code"].presence || item["name"].to_s.downcase] = product
      end
    end

    def copy_errors(record)
      record.errors.full_messages.each { errors.add :base, _1 }
    end
end
