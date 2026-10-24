# The debit note that goes with goods sent back: what's being returned and why, and what it comes
# to with VAT, for the supplier to credit.
class SupplierReturnPdf < DocumentPdf
  COLUMNS = [ [ "Item", 215 ], [ "Qty", 60 ], [ "Unit cost", 80 ], [ "VAT", 60 ], [ "Total", 100 ] ].freeze

  def initialize(supplier_return)
    @return = supplier_return
    super(account: supplier_return.account, branch: supplier_return.branch)
  end

  def title = "Debit note"
  def reference = @return.reference

  private
    def columns = COLUMNS

    def numeric_from = 1

    def details
      [ "Date #{date(@return.created_at)}", ("Delivery #{@return.goods_receipt.reference}" if @return.goods_receipt),
        ("Your delivery note #{@return.goods_receipt.supplier_reference}" if @return.goods_receipt&.supplier_reference.present?),
        ("Amounts in #{@return.currency}" if @return.supplier.foreign?) ]
    end

    def content
      supplier = @return.supplier
      two_blocks "To", [ supplier.name, supplier.contact_name, supplier.phone, supplier.email, supplier.address ],
        "From", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      table(@return.lines.includes(:stock_batch, product: :unit).map do |line|
        [ [ line.product.name, line.product.sku, ("batch #{line.stock_batch.number}" if line.stock_batch) ].compact.join(" · "),
          "#{quantity(line.quantity)} #{line.product.unit.abbreviation}", money(line.unit_cost_cents),
          "#{line.tax_rate.to_d.to_s("F").delete_suffix(".0")}%", money(line.total_cents) ]
      end)
      total "VAT", @return.tax_cents, size: 10, style: :normal, currency: @return.currency
      total "To be credited", @return.total_cents, currency: @return.currency

      pdf.move_down 20
      note "Returned because: #{@return.reason.humanize.downcase}#{". #{@return.note}" if @return.note.present?}"
      note "Please send a credit note quoting #{@return.reference}. The goods left our store on #{date(@return.created_at)}."
      note "Returned by #{@return.creator.name}" if @return.creator
    end
end
