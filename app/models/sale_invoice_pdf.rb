# An A4 tax invoice for a sale to a named customer, for trade customers who need more than the
# till receipt. For a sale on account it shows when payment is due.
class SaleInvoicePdf < DocumentPdf
  COLUMNS = [ [ "Item", 215 ], [ "Qty", 60 ], [ "Unit price", 75 ], [ "Discount", 65 ], [ "Total", 100 ] ].freeze

  def initialize(sale)
    @sale = sale
    super(account: sale.account, branch: sale.branch)
  end

  def title = "Tax invoice"
  def reference = @sale.receipt_number

  private
    def columns = COLUMNS

    def numeric_from = 1

    def on_account_cents
      @sale.payments.select(&:on_account?).sum(&:amount_cents)
    end

    def details
      [ "Date #{date(@sale.completed_at)}",
        ("Due #{date(@sale.customer.due_date_for(@sale))}" if on_account_cents.positive?),
        ("Order #{@sale.customer_order.reference}" if @sale.customer_order),
        ("Job: #{@sale.job.label}" if @sale.job) ]
    end

    def content
      customer = @sale.customer
      two_blocks "Bill to", [ customer.name, customer.phone, customer.email, customer.address, ("PIN #{customer.tax_pin}" if customer.tax_pin.present?) ],
        "From", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      table(@sale.lines.includes(product: :unit, product_unit: :unit).map do |line|
        [ line.description, "#{quantity(line.quantity)} #{line.unit.abbreviation}", money(line.unit_price_cents),
          (line.discount_cents.positive? ? money(line.discount_cents) : ""), money(line.total_cents) ]
      end)
      total "Discount", @sale.discount_cents, size: 10, style: :normal if @sale.discount_cents.positive?
      total "Total", @sale.total_cents
      total "includes tax", @sale.tax_cents, size: 9, style: :normal
      @sale.payments.each { total _1.label, _1.amount_cents, size: 9, style: :normal }

      pdf.move_down 20
      note "Payment of #{Money.format(on_account_cents, currency: account.currency)} on account is due by #{date(customer.due_date_for(@sale))}." if on_account_cents.positive?
      note account.receipt_footer if account.receipt_footer.present?
    end
end
