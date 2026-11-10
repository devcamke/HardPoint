# A credit note for goods brought back (a sale return), on the shop's letterhead: what came back, at what it was
# sold for, against which receipt, and how it was refunded.
class CreditNotePdf < DocumentPdf
  COLUMNS = [ [ "Item", 255 ], [ "Qty", 70 ], [ "Restocked", 80 ], [ "Credit", 110 ] ].freeze

  def initialize(sale_return)
    @return = sale_return
    super(account: sale_return.account, branch: sale_return.branch)
  end

  def title = "Credit note"
  def reference = @return.return_number

  private
    def columns = COLUMNS

    def numeric_from = 1

    def customer_facing? = true

    def details
      [ "Date #{date(@return.created_at)}", "Against receipt #{@return.sale.receipt_number}" ]
    end

    def content
      customer = @return.sale.customer
      two_blocks "Credited to", (customer ? [ customer.name, customer.phone, customer.email, ("PIN #{customer.tax_pin}" if customer.tax_pin.present?) ] : [ "Walk-in customer" ]),
        "From", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      table(@return.lines.includes(sale_line: [ :product, { product_unit: :unit } ]).map do |line|
        [ line.sale_line.description, quantity(line.quantity), line.restock? ? "Yes" : "No", money(line.total_cents) ]
      end)
      total "Total credited", @return.total_cents
      total "includes tax", @return.tax_cents, size: 9, style: :normal
      pdf.move_down 12
      note "Refunded #{Sale::Voidable::REFUND_WORDS.fetch(@return.refund_method, @return.refund_method.humanize.downcase)}."
      note "Reason: #{@return.reason}" if @return.reason.present?
    end
end
