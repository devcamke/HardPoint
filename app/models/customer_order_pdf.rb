# A quote or order for the customer, prices including tax.
class CustomerOrderPdf < DocumentPdf
  COLUMNS = [ [ "Item", 235 ], [ "Code", 70 ], [ "Qty", 55 ], [ "Unit price", 75 ], [ "Total", 80 ] ].freeze

  def initialize(customer_order)
    @order = customer_order
    super(account: customer_order.account, branch: customer_order.branch)
  end

  def title = @order.kind
  def reference = @order.reference

  private
    def columns = COLUMNS

    def details
      [ "Date #{date(@order.ordered_at || @order.created_at)}",
        ("Valid until #{date(@order.valid_until)}" if @order.quote? && @order.valid_until),
        ("Needed by #{date(@order.needed_by)}" if @order.needed_by),
        ("Job: #{@order.job.label}" if @order.job) ]
    end

    def content
      customer = @order.customer
      two_blocks "For", [ customer.name, customer.phone, customer.email, customer.address, ("PIN #{customer.tax_pin}" if customer.tax_pin.present?) ],
        "From", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      table(@order.lines.includes(product: :unit, product_unit: :unit).map do |line|
        [ line.description, line.product.sku, "#{quantity(line.quantity)} #{line.unit.abbreviation}", money(line.unit_price_cents), money(line.total_cents) ]
      end)
      total "Total", @order.total_cents
      total "includes tax", @order.tax_cents, size: 9, style: :normal
      deposits = @order.deposit_balance_cents
      if deposits.positive? && !@order.collected?
        total "Deposit paid", deposits, size: 10, style: :normal
        total "To pay on collection", @order.total_cents - deposits
      end

      pdf.move_down 20
      note "Note: #{@order.note}" if @order.note.present?
      if @order.quote?
        note "Prices include tax and hold until #{date(@order.valid_until)}. Quote #{@order.reference} to order." if @order.valid_until
      else
        note "Please bring #{@order.reference} when you collect."
      end
    end
end
