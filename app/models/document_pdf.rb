# The shop's A4 letterhead: purchase orders, quotes and orders, invoices, statements and delivery
# notes all share it. Subclasses give the #title, #reference, #details (lines under the reference),
# #columns and draw their own #content with the helpers here.
class DocumentPdf
  NAVY = "102A43"
  ORANGE = "F76707"
  GREY = "5B6573"
  CONCRETE = "F5F4F1"
  RULE = "E7E5E0"
  FONTS = Rails.root.join("vendor/fonts")
  # The A4 page less its margins (595 − 2 × 40), upright.
  WIDTH = 515

  attr_reader :account, :branch

  def initialize(account:, branch:)
    @account = account
    @branch = branch
  end

  def render
    Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: 40, info: { Title: "#{title} #{reference}", Creator: "HardPoint" }) do |pdf|
      @pdf = pdf
      # DejaVu Sans covers the characters product names use (½, ×, é…); Prawn's built-in fonts don't.
      pdf.font_families.update("DejaVu" => { normal: FONTS.join("DejaVuSans.ttf").to_s, bold: FONTS.join("DejaVuSans-Bold.ttf").to_s })
      pdf.font "DejaVu"
      letterhead
      content
    end.render
  end

  def filename
    "#{reference}.pdf"
  end

  private
    attr_reader :pdf

    def details
      []
    end

    def page_layout
      :portrait
    end

    # Columns from this index on are numbers, aligned right.
    def numeric_from
      2
    end

    def alignment(index)
      index >= numeric_from ? :right : :left
    end

    def letterhead
      pdf.fill_color NAVY
      pdf.text account.name, size: 18, style: :bold
      pdf.fill_color GREY
      pdf.text [ branch&.name, branch&.address, branch&.phone ].compact_blank.join(" · ").presence || "All branches", size: 9
      pdf.move_up 34
      pdf.fill_color ORANGE
      pdf.text title.upcase, size: 16, style: :bold, align: :right
      pdf.fill_color NAVY
      pdf.text reference, size: 12, align: :right
      pdf.fill_color GREY
      details.compact_blank.each { pdf.text _1, size: 9, align: :right }
      pdf.move_down 16
    end

    def two_blocks(left_title, left_lines, right_title, right_lines)
      top = pdf.cursor
      heights = [ [ 0, left_title, left_lines ], [ 270, right_title, right_lines ] ].map do |x, title, lines|
        pdf.bounding_box([ x, top ], width: 245) { block title, lines }
        top - pdf.cursor
      end
      pdf.move_cursor_to top - heights.max
      pdf.move_down 16
    end

    def block(title, lines)
      pdf.fill_color GREY
      pdf.text title.upcase, size: 8, style: :bold
      pdf.fill_color NAVY
      lines.compact_blank.each { pdf.text _1, size: 10 }
    end

    def table(rows)
      row columns.map(&:first), bold: true, fill: CONCRETE
      rows.each do |cells|
        if pdf.cursor < 80
          pdf.start_new_page
          row columns.map(&:first), bold: true, fill: CONCRETE
        end
        row cells
      end
      pdf.move_down 6
    end

    def row(cells, bold: false, fill: nil)
      height = cells.zip(columns).map { |cell, (_, width)| pdf.height_of(cell.to_s, width: width - 8, size: 9, style: (bold ? :bold : :normal)) }.max + 8
      top = pdf.cursor
      if fill
        pdf.fill_color fill
        pdf.fill_rectangle [ 0, top ], pdf.bounds.width, height
      end
      pdf.fill_color NAVY
      x = 0
      cells.zip(columns).each_with_index do |(cell, (_, width)), index|
        pdf.text_box cell.to_s, at: [ x + 4, top - 4 ], width: width - 8, height: height, size: 9,
          style: (bold ? :bold : :normal), align: alignment(index)
        x += width
      end
      pdf.stroke_color RULE
      pdf.stroke_horizontal_line 0, pdf.bounds.width, at: top - height
      pdf.move_down height
    end

    def total(label, cents, size: 12, style: :bold, currency: account.currency)
      pdf.fill_color NAVY
      pdf.text "#{label}  #{Money.format(cents, currency: currency)}", size: size, style: style, align: :right
    end

    def note(text)
      pdf.fill_color GREY
      pdf.text text, size: 9
    end

    def money(cents)
      ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", cents / 100.0))
    end

    def quantity(amount)
      amount.to_d.to_s("F").delete_suffix(".0")
    end

    def date(value)
      value.to_date.to_fs(:long)
    end
end
