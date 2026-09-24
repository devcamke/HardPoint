# The delivery note that travels with the goods, with space for the customer to sign.
class DeliveryNotePdf < DocumentPdf
  COLUMNS = [ [ "Item", 290 ], [ "Code", 100 ], [ "Qty", 125 ] ].freeze

  def initialize(delivery_note)
    @note = delivery_note
    super(account: delivery_note.account, branch: delivery_note.branch)
  end

  def title = "Delivery note"
  def reference = @note.reference

  private
    def columns = COLUMNS

    def details
      [ "Date #{date(@note.dispatched_at || @note.created_at)}", "Sale #{@note.sale.receipt_number}",
        ("Order #{@note.sale.customer_order.reference}" if @note.sale.customer_order) ]
    end

    def content
      two_blocks "Deliver to", [ @note.customer&.name, @note.address, @note.contact_phone ],
        "Dispatched by", [ "#{account.name}, #{branch.name}", branch.phone, ("Driver #{@note.driver_name}" if @note.driver_name),
          ("Vehicle #{@note.vehicle}" if @note.vehicle) ]

      table(@note.sale.lines.includes(product: :unit, product_unit: :unit).map do |line|
        [ line.description, line.product.sku, "#{quantity(line.quantity)} #{line.unit.abbreviation}" ]
      end)

      pdf.move_down 10
      note "Note: #{@note.note}" if @note.note.present?
      pdf.move_down 40
      pdf.fill_color NAVY
      pdf.text "Received in good order by: ______________________________   Signature: __________________   Date: ____________", size: 9
    end
end
