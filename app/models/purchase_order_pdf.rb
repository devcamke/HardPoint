# The purchase order as a one- or multi-page A4 PDF, attached to the email to the supplier.
class PurchaseOrderPdf < DocumentPdf
  COLUMNS = [ [ "Item", 200 ], [ "Your code", 70 ], [ "Qty", 55 ], [ "Unit", 40 ], [ "Unit cost", 72 ], [ "Total", 78 ] ].freeze

  def initialize(purchase_order)
    @order = purchase_order
    super(account: purchase_order.account, branch: purchase_order.branch)
  end

  def title = "Purchase order"
  def reference = @order.reference

  private
    def columns = COLUMNS

    def details
      [ "Date #{date(@order.sent_at || @order.created_at)}", ("Deliver by #{date(@order.expected_on)}" if @order.expected_on) ]
    end

    def content
      supplier = @order.supplier
      two_blocks "Supplier", [ supplier.name, supplier.contact_name, supplier.phone, supplier.email, supplier.address ],
        "Deliver to", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      table(@order.lines.includes(product: :unit).map do |line|
        [ "#{line.product.name}\n#{line.product.sku}", line.supplier_product&.supplier_sku.to_s, quantity(line.quantity),
          line.product.unit.abbreviation, money(line.unit_cost_cents), money(line.line_total_cents) ]
      end)
      total "Total", @order.total_cents

      pdf.move_down 20
      note "Note: #{@order.note}" if @order.note.present?
      note "Please quote #{@order.reference} on your delivery note and invoice."
      note "Ordered by #{@order.creator.name}" if @order.creator
    end
end
