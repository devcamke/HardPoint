# A receipt as plain lines and amounts, for printing straight to a receipt printer (ESC/POS
# through QZ Tray). The offline till builds the same shape in the browser.
class ReceiptData
  def initialize(sale)
    @sale = sale
    @account = sale.account
  end

  def as_json(*)
    { header: [ @account.name, @sale.branch.name, @sale.branch.address, (@sale.branch.phone && "Tel #{@sale.branch.phone}") ].compact_blank,
      receipt_number: @sale.receipt_number, time: I18n.l(@sale.completed_at || @sale.created_at, format: :short),
      register: @sale.register.name, cashier: @sale.cashier.name, customer: @sale.customer&.name, job: @sale.job&.label, voided: @sale.voided?,
      lines: @sale.lines.includes(:product, :promotion, product_unit: :unit).map { |line| line_json(line) },
      saved: (amount(saved_cents) if saved_cents.positive?),
      subtotal: (amount(@sale.subtotal_cents) if @sale.discount_cents.positive?), discount: (amount(@sale.discount_cents) if @sale.discount_cents.positive?),
      total: money(@sale.total_cents), tax: money(@sale.tax_cents),
      payments: @sale.payments.map { |payment| { label: [ payment.label, payment.reference ].compact.join(" "), amount: money(payment.cash? || payment.foreign_cash? ? payment.tendered_cents : payment.amount_cents) } },
      change: (money(@sale.change_cents) if @sale.change_cents.positive?),
      loyalty: loyalty_lines,
      etims: etims_json, footer: @account.receipt_footer.presence || "Thank you for shopping with us",
      open_drawer: @sale.payments.any? { _1.cash? || _1.foreign_cash? } }
  end

  private
    def line_json(line)
      { description: line.description, detail: "#{ActiveSupport::NumberHelper.number_to_rounded(line.quantity, precision: 3, strip_insignificant_zeros: true)} #{line.unit.abbreviation} x #{amount(line.unit_price_cents)}",
        total: amount(line.total_cents), discount: (amount(line.discount_cents) if line.discount_cents.positive?),
        promotion: ([ line.promotion&.offer || "promotion", amount(line.promotion_discount_cents) ] if line.promotion_discount_cents.positive?) }
    end

    def loyalty_lines
      return unless @sale.completed? && @sale.loyalty_program

      [ "Points earned: #{@sale.points_earned}", "Points balance: #{@sale.customer.points_balance}" ]
    end

    def saved_cents
      @sale.lines.sum(&:promotion_discount_cents)
    end

    def etims_json
      submission = @sale.etims_submission
      return unless submission
      return { lines: [ "Tax invoice being sent to KRA.", "Ask for a reprint for the signed copy." ] } unless submission.sent?

      { lines: [ "KRA eTIMS", "SCU ID: #{submission.device.sdc_id}", "CU invoice: #{submission.device.sdc_id}/#{submission.receipt_number}",
                 "Internal data: #{submission.internal_data}", "Signature: #{submission.receipt_signature}" ], qr: submission.verification_url }
    end

    def money(cents) = Money.format(cents, currency: @account.currency)
    def amount(cents) = ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", cents / 100.0))
end
