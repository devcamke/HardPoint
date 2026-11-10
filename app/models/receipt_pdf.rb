# A sale's receipt as a PDF the shape of the till roll (80 mm wide, as long as it needs), to share or save as a picture:
# the same lines, totals, payments and KRA eTIMS signature as the printed one, with the shop's logo and colour.
class ReceiptPdf
  WIDTH = 226.77 # 80 mm
  MARGIN = 12
  INNER = WIDTH - 2 * MARGIN

  def initialize(sale)
    @sale = sale
    @account = sale.account
  end

  def filename = "receipt-#{@sale.receipt_number}.pdf"

  # Drawn once on a long page to measure it, then again on a page cut to fit.
  def render
    height = document(5000) { |pdf| draw(pdf) }.then { |pdf| 5000 - pdf.cursor + 2 * MARGIN }
    document(height) { |pdf| draw(pdf) }.render
  end

  private
    attr_reader :sale, :account

    def document(height, &)
      Prawn::Document.new(page_size: [ WIDTH, height ], margin: MARGIN, info: { Title: "Receipt #{sale.receipt_number}", Creator: "HardPoint" }).tap do |pdf|
        pdf.font_families.update("DejaVu" => { normal: DocumentPdf::FONTS.join("DejaVuSans.ttf").to_s, bold: DocumentPdf::FONTS.join("DejaVuSans-Bold.ttf").to_s })
        pdf.font "DejaVu"
        yield pdf
      end
    end

    def draw(pdf)
      @pdf = pdf
      header
      rule
      row "Receipt", sale.receipt_number, bold: true
      row I18n.l(sale.completed_at || sale.created_at, format: :short), sale.register.name
      row "Served by", sale.cashier.name
      row "Customer", sale.customer.name if sale.customer
      centred "*** VOIDED ***", bold: true if sale.voided?
      rule
      lines
      rule
      totals
      rule
      payments
      etims
      rule
      centred account.receipt_footer.presence || "Thank you for shopping with us", size: 7.5
    end

    def header
      if (logo = logo_image)
        @pdf.image logo, fit: [ INNER, 50 ], position: :center
        @pdf.move_down 4
      end
      @pdf.fill_color account.theme_color.delete("#")
      centred account.name, size: 11, bold: true
      @pdf.fill_color "1F2937"
      centred [ sale.branch.name, sale.branch.address, ("Tel #{sale.branch.phone}" if sale.branch.phone.present?) ].compact_blank.join(" · "), size: 7
    end

    def lines
      sale.lines.includes(:product, :promotion, product_unit: :unit).each do |line|
        @pdf.text line.description, size: 8
        row "#{quantity(line.quantity)} #{line.unit.abbreviation} × #{amount(line.unit_price_cents)}", amount(line.total_cents), size: 7.5, muted: true
        row "  discount", "−#{amount(line.discount_cents)}", size: 7, muted: true if line.discount_cents.positive?
        row "  #{line.promotion&.offer || "promotion"}", "−#{amount(line.promotion_discount_cents)}", size: 7, muted: true if line.promotion_discount_cents.positive?
        @pdf.text "  S/N #{line.serial_number}", size: 7 if line.serial_number.present?
        @pdf.move_down 2
      end
    end

    def totals
      if sale.discount_cents.positive?
        row "Subtotal", money(sale.subtotal_cents)
        row "Discount", "−#{money(sale.discount_cents)}"
      end
      row "TOTAL", money(sale.total_cents), size: 11, bold: true
      row "Incl. tax", money(sale.tax_cents), size: 7.5, muted: true
    end

    def payments
      sale.payments.each do |payment|
        row "#{payment.label}#{" #{payment.reference}" if payment.reference}", money(payment.cash? || payment.foreign_cash? ? payment.tendered_cents : payment.amount_cents)
      end
      row "Change", money(sale.change_cents), bold: true if sale.change_cents.positive?
    end

    def etims
      submission = sale.etims_submission
      return unless submission&.sent?

      rule
      centred "KRA eTIMS", bold: true
      row "SCU ID", submission.device.sdc_id, size: 7.5
      row "CU invoice no.", "#{submission.device.sdc_id}/#{submission.receipt_number}", size: 7.5
      @pdf.text "Receipt signature: #{submission.receipt_signature.to_s.scan(/.{1,4}/).join("-")}", size: 6.5
      qr(submission.verification_url) if submission.verification_url.present?
    end

    # Squares straight from the QR code's modules: crisp at any zoom.
    def qr(text)
      modules = RQRCode::QRCode.new(text).modules
      size = 90.0 / modules.size
      left = (INNER - 90) / 2
      top = @pdf.cursor - 4
      @pdf.fill_color "000000"
      modules.each_with_index do |row, y|
        row.each_with_index { |dark, x| @pdf.fill_rectangle [ left + x * size, top - y * size ], size, size if dark }
      end
      @pdf.move_down 98
      @pdf.fill_color "1F2937"
    end

    def row(left, right, size: 8, bold: false, muted: false)
      @pdf.fill_color muted ? "6B7280" : "1F2937"
      style = bold ? :bold : :normal
      top = @pdf.cursor
      @pdf.text_box left.to_s, at: [ 0, top ], width: INNER * 0.62, size: size, style: style, overflow: :shrink_to_fit, height: size * 1.4
      @pdf.text_box right.to_s, at: [ INNER * 0.62, top ], width: INNER * 0.38, size: size, style: style, align: :right, overflow: :shrink_to_fit, height: size * 1.4
      @pdf.move_down size * 1.45
      @pdf.fill_color "1F2937"
    end

    def centred(text, size: 8, bold: false) = @pdf.text(text, size: size, style: bold ? :bold : :normal, align: :center)

    def rule
      @pdf.move_down 3
      @pdf.dash 2, space: 2
      @pdf.stroke_color "9CA3AF"
      @pdf.stroke_horizontal_rule
      @pdf.undash
      @pdf.move_down 5
    end

    def money(cents) = Money.format(cents, currency: account.currency)
    def amount(cents) = ActiveSupport::NumberHelper.number_to_delimited(format("%.2f", cents.to_i / 100.0))
    def quantity(amount) = amount.to_d.frac.zero? ? amount.to_i.to_s : amount.to_d.round(3).to_s("F")

    def logo_image
      return @logo_image if defined?(@logo_image)

      @logo_image = (StringIO.new(account.logo.variant(resize_to_limit: [ 640, 200 ], format: :png).processed.download) if account.logo.attached?)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { account_id: account.id })
      @logo_image = nil
    end
end
