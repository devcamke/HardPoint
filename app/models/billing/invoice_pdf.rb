# HardPoint's invoice to a shop, on HardPoint's letterhead rather than the shop's.
class Billing::InvoicePdf < DocumentPdf
  COLUMNS = [ [ "Description", 335 ], [ "Period", 100 ], [ "Amount", 80 ] ].freeze

  def initialize(invoice)
    @invoice = invoice
    super(account: invoice.account, branch: nil)
  end

  def title = @invoice.paid? ? "Paid invoice" : "Invoice"
  def reference = @invoice.number

  private
    def columns = COLUMNS

    def details
      [ "Date #{date(@invoice.created_at)}", (@invoice.paid? ? "Paid #{date(@invoice.paid_at)}" : "Due #{date(@invoice.due_on)}") ]
    end

    def letterhead
      company = Billing.company
      pdf.fill_color NAVY
      pdf.text company[:name].to_s, size: 18, style: :bold
      pdf.fill_color GREY
      pdf.text [ company[:address], company[:email], ("PIN #{company[:tax_pin]}" if company[:tax_pin]) ].compact_blank.join(" · "), size: 9
      pdf.move_up 34
      pdf.fill_color ORANGE
      pdf.text title.upcase, size: 16, style: :bold, align: :right
      pdf.fill_color NAVY
      pdf.text reference, size: 12, align: :right
      pdf.fill_color GREY
      details.compact_blank.each { pdf.text _1, size: 9, align: :right }
      pdf.move_down 16
    end

    def content
      two_blocks "Billed to", [ account.name, "#{account.subdomain}.#{Rails.configuration.x.webhook_url_options[:host]}", *account.billing_recipients ],
        "Plan", [ "#{@invoice.plan_name} plan", Plan.find(@invoice.plan).price + " a month" ]
      table [ [ "HardPoint #{@invoice.plan_name} plan", "#{@invoice.period_start.strftime("%-d %b")} – #{(@invoice.period_end - 1).strftime("%-d %b %Y")}", money(@invoice.amount_cents) ] ]
      total "Total (#{@invoice.currency})", @invoice.amount_cents
      pdf.move_down 20
      note @invoice.paid? ? "Paid with thanks." : "Pay by M-Pesa or card from the Billing page in HardPoint, quoting #{@invoice.number}."
    end
end
