# A sale, void or return in the shape OSCU's saveTrnsSalesOsdc wants. Prices include tax;
# amounts are shillings; cart discounts are spread over the lines, as on the receipt.
class Etims::Invoice
  Line = Data.define(:product, :description, :unit, :quantity, :unit_price_cents, :gross_cents, :total_cents, :tax_cents, :tax_rate, :tax_rate_record)

  TAX_RATES = { "A" => 0, "B" => 16, "C" => 0, "D" => 0, "E" => 8 }.freeze
  REFUND_REASONS = { "return" => "06", "void" => "13" }.freeze

  def initialize(submission)
    @submission = submission
    @document = submission.document
    @device = submission.device
  end

  def products
    lines.map(&:product).uniq
  end

  def lines
    @lines ||= case @document
    when SaleReturn then return_lines
    else sale_lines
    end
  end

  def to_h
    items = lines.each_with_index.map { |line, index| item(line, index + 1) }
    totals = TAX_RATES.keys.to_h { |type| [ type, items.select { _1[:taxTyCd] == type } ] }

    { invcNo: @submission.invoice_number, orgInvcNo: @submission.original_invoice_number || 0,
      custTin: customer_pin, custNm: customer&.name, salesTyCd: "N", rcptTyCd: @submission.credit_note? ? "R" : "S",
      pmtTyCd: payment_type, salesSttsCd: "02", cfmDt: happened_at.strftime("%Y%m%d%H%M%S"), salesDt: happened_at.strftime("%Y%m%d"),
      stockRlsDt: happened_at.strftime("%Y%m%d%H%M%S"), rfdDt: (happened_at.strftime("%Y%m%d%H%M%S") if @submission.credit_note?),
      rfdRsnCd: (REFUND_REASONS[@document.is_a?(SaleReturn) ? "return" : "void"] if @submission.credit_note?),
      totItemCnt: items.size,
      **TAX_RATES.keys.to_h { |type| [ :"taxblAmt#{type}", shillings(totals[type].sum { _1[:taxblAmt] }) ] },
      **TAX_RATES.to_h { |type, rate| [ :"taxRt#{type}", rate ] },
      **TAX_RATES.keys.to_h { |type| [ :"taxAmt#{type}", shillings(totals[type].sum { _1[:taxAmt] }) ] },
      totTaxblAmt: shillings(items.sum { _1[:taxblAmt] }), totTaxAmt: shillings(items.sum { _1[:taxAmt] }), totAmt: shillings(items.sum { _1[:totAmt] }),
      prchrAcptcYn: "N", remark: @submission.document_label, regrId: cashier&.id.to_s, regrNm: cashier&.name, modrId: cashier&.id.to_s, modrNm: cashier&.name,
      receipt: { custTin: customer_pin, custMblNo: customer&.phone, rptNo: nil, trdeNm: account.name, adrs: sale.branch.address,
                 topMsg: account.name, btmMsg: account.receipt_footer.to_s.first(100), prchrAcptcYn: "N" },
      itemList: items.map { |item| item.merge(item.slice(:taxblAmt, :taxAmt, :totAmt).transform_values { shillings(_1) }) } }
  end

  private
    def account = @document.account
    def sale = @document.is_a?(SaleReturn) ? @document.sale : @document
    def customer = sale.customer
    def cashier = @document.is_a?(SaleReturn) ? @document.creator : sale.cashier

    # KRA refuses an invoice whose buyer PIN isn't a PIN; one saved before PINs were checked is left off.
    def customer_pin
      customer&.tax_pin if customer&.tax_pin.to_s.match?(Etims::PIN_FORMAT)
    end

    def happened_at
      time = case @document
      when SaleReturn then @document.created_at
      else @submission.credit_note? ? @document.voided_at : @document.completed_at
      end
      (time || Time.current).in_time_zone("Nairobi")
    end

    # The largest tender. A deposit was money taken on an earlier day, so when the customer paid the
    # rest some other way today, that way is how the sale was paid.
    def payment_type
      tender = if @document.is_a?(SaleReturn)
        @document.refund_method
      else
        paid_today = sale.payments.reject(&:deposit?)
        (paid_today.presence || sale.payments).max_by(&:amount_cents)&.tender
      end
      Etims::PAYMENT_TYPES.fetch(tender.to_s, "07")
    end

    # Each line's share of the cart discount is rounded to the cent, so the odd cents left over go on the
    # last line (the last taxed one, for the tax): KRA's totals are then the receipt's to the cent.
    def sale_lines
      share = sale.subtotal_cents.zero? ? 0 : sale.total_cents.to_r / sale.subtotal_cents
      lines = sale.lines.includes(:product, :tax_rate_record, product_unit: :unit).map do |line|
        Line.new(line.product, line.description, line.unit, line.quantity, line.unit_price_cents, line.gross_cents,
          (line.total_cents * share).round, (line.tax_cents * share).round, line.tax_rate, line.tax_rate_record)
      end
      return lines if lines.empty?

      total_left = sale.total_cents - lines.sum(&:total_cents)
      lines[-1] = lines[-1].with(total_cents: lines[-1].total_cents + total_left)
      tax_left = sale.tax_cents - lines.sum(&:tax_cents)
      taxed = lines.rindex { _1.tax_cents.nonzero? } || lines.size - 1
      lines[taxed] = lines[taxed].with(tax_cents: lines[taxed].tax_cents + tax_left)
      lines
    end

    def return_lines
      @document.lines.includes(sale_line: [ :product, :tax_rate_record, { product_unit: :unit } ]).map do |line|
        sold = line.sale_line
        Line.new(sold.product, sold.description, sold.unit, line.quantity, sold.unit_price_cents, (sold.unit_price_cents * line.quantity).round,
          line.total_cents, line.tax_cents, sold.tax_rate, sold.tax_rate_record)
      end
    end

    # Line amounts stay in cents here so the totals add up exactly; they're sent as shillings.
    def item(line, sequence)
      discount = line.gross_cents - line.total_cents
      { itemSeq: sequence, itemCd: Etims::Item.code_for(line.product), itemClsCd: line.product.category&.etims_class_code.presence || @device.default_item_class_code,
        itemNm: line.description, bcd: nil, pkgUnitCd: "NT", pkg: 1, qtyUnitCd: line.unit.etims_code.presence || "U", qty: line.quantity.to_f,
        prc: shillings(line.unit_price_cents), splyAmt: shillings(line.gross_cents),
        dcRt: line.gross_cents.zero? ? 0 : (discount * 100.0 / line.gross_cents).round(2), dcAmt: shillings(discount),
        isrccCd: nil, isrccNm: nil, isrcRt: nil, isrcAmt: nil, taxTyCd: Etims.tax_type_for(account, line.tax_rate, tax_rate: line.tax_rate_record),
        taxblAmt: line.total_cents, taxAmt: line.tax_cents, totAmt: line.total_cents }
    end

    def shillings(cents)
      (cents / 100.0).round(2)
    end
end
