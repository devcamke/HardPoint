# The purchase order as a one- or multi-page A4 PDF, attached to the email to the supplier.
class PurchaseOrderPdf
  NAVY = "102A43"
  ORANGE = "F76707"
  GREY = "5B6573"
  FONTS = Rails.root.join("vendor/fonts")
  # Widths add up to the A4 page less its margins (595 − 2 × 40 = 515pt).
  COLUMNS = [ [ "Item", 200 ], [ "Your code", 70 ], [ "Qty", 55 ], [ "Unit", 40 ], [ "Unit cost", 72 ], [ "Total", 78 ] ].freeze

  def initialize(purchase_order)
    @order = purchase_order
    @account = purchase_order.account
  end

  def render
    Prawn::Document.new(page_size: "A4", margin: 40, info: { Title: "Purchase order #{@order.reference}", Creator: "HardPoint" }) do |pdf|
      # DejaVu Sans covers the characters product names use (½, ×, é…); Prawn's built-in fonts don't.
      pdf.font_families.update("DejaVu" => { normal: FONTS.join("DejaVuSans.ttf").to_s, bold: FONTS.join("DejaVuSans-Bold.ttf").to_s })
      pdf.font "DejaVu"
      header(pdf)
      addresses(pdf)
      lines(pdf)
      footer(pdf)
    end.render
  end

  def filename
    "#{@order.reference}.pdf"
  end

  private
    def header(pdf)
      pdf.fill_color NAVY
      pdf.text @account.name, size: 18, style: :bold
      pdf.fill_color GREY
      pdf.text [ @order.branch.name, @order.branch.address, @order.branch.phone ].compact_blank.join(" · "), size: 9
      pdf.move_up 34
      pdf.fill_color ORANGE
      pdf.text "PURCHASE ORDER", size: 16, style: :bold, align: :right
      pdf.fill_color NAVY
      pdf.text @order.reference, size: 12, align: :right
      pdf.fill_color GREY
      pdf.text "Date #{(@order.sent_at || @order.created_at).to_date.to_fs(:long)}", size: 9, align: :right
      pdf.text "Deliver by #{@order.expected_on.to_fs(:long)}", size: 9, align: :right if @order.expected_on
      pdf.move_down 16
    end

    def addresses(pdf)
      top = pdf.cursor
      pdf.bounding_box([ 0, top ], width: 250) do
        block pdf, "Supplier", [ @order.supplier.name, @order.supplier.contact_name, @order.supplier.phone, @order.supplier.email, @order.supplier.address ]
      end
      pdf.bounding_box([ 270, top ], width: 250) do
        block pdf, "Deliver to", [ "#{@account.name}, #{@order.branch.name}", @order.branch.address, @order.branch.phone ]
      end
      pdf.move_down 16
    end

    def block(pdf, title, lines)
      pdf.fill_color GREY
      pdf.text title.upcase, size: 8, style: :bold
      pdf.fill_color NAVY
      lines.compact_blank.each { pdf.text _1, size: 10 }
    end

    def lines(pdf)
      row pdf, COLUMNS.map(&:first), bold: true, fill: "F5F4F1"
      @order.lines.includes(product: :unit).each do |line|
        pdf.start_new_page if pdf.cursor < 80
        supplier_code = line.supplier_product&.supplier_sku
        row pdf, [ "#{line.product.name}\n#{line.product.sku}", supplier_code.to_s, quantity(line.quantity), line.product.unit.abbreviation,
                   money(line.unit_cost_cents), money(line.line_total_cents) ]
      end
      pdf.move_down 6
      pdf.fill_color NAVY
      pdf.text "Total  #{Money.format(@order.total_cents, currency: @account.currency)}", size: 12, style: :bold, align: :right
    end

    def row(pdf, cells, bold: false, fill: nil)
      height = cells.map { |cell| cell.to_s.lines.count }.max * 12 + 8
      top = pdf.cursor
      if fill
        pdf.fill_color fill
        pdf.fill_rectangle [ 0, top ], pdf.bounds.width, height
      end
      pdf.fill_color NAVY
      x = 0
      cells.zip(COLUMNS).each_with_index do |(cell, (_, width)), index|
        pdf.text_box cell.to_s, at: [ x + 4, top - 4 ], width: width - 8, height: height, size: 9,
          style: (bold ? :bold : :normal), align: (index >= 2 ? :right : :left)
        x += width
      end
      pdf.stroke_color "E7E5E0"
      pdf.stroke_horizontal_line 0, pdf.bounds.width, at: top - height
      pdf.move_down height
    end

    def footer(pdf)
      pdf.move_down 20
      pdf.fill_color GREY
      pdf.text "Note: #{@order.note}", size: 9 if @order.note.present?
      pdf.text "Please quote #{@order.reference} on your delivery note and invoice.", size: 9
      pdf.text "Ordered by #{@order.creator&.name}", size: 9 if @order.creator
    end

    def money(cents)
      ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", cents / 100.0))
    end

    def quantity(amount)
      amount.to_d.to_s("F").delete_suffix(".0")
    end
end
