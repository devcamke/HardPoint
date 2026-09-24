# The hire agreement the customer signs when the tools go out.
class HireAgreementPdf < DocumentPdf
  COLUMNS = [ [ "Tool", 190 ], [ "Asset tag", 70 ], [ "Per day", 70 ], [ "Per week", 70 ], [ "Deposit", 85 ] ].freeze
  TERMS = [
    "The tools remain the property of the shop. They are hired for use at the site given and may not be lent or hired to anyone else.",
    "Charges run from the time the tools go out until they are returned, by the day (24 hours, with one hour's grace), or by the week where a weekly rate is shown.",
    "The hirer returns the tools clean and in the condition they were received, and pays for repairs or replacement if they are damaged, lost or stolen.",
    "The deposit is set against the charges when the tools come back; any balance is paid or refunded then.",
    "Tools kept past the return time continue to be charged. The shop may collect tools not returned within 3 days of the return time."
  ].freeze

  def initialize(agreement)
    @agreement = agreement
    super(account: agreement.account, branch: agreement.branch)
  end

  def title = "Hire agreement"
  def reference = @agreement.reference

  private
    def columns = COLUMNS

    def details
      [ "Out #{time(@agreement.started_at)}", "Due back #{time(@agreement.due_back_at)}" ]
    end

    def content
      customer = @agreement.customer
      two_blocks "Hirer", [ customer.name, customer.phone, ("ID #{@agreement.id_number}" if @agreement.id_number.present?), ("Site: #{@agreement.site}" if @agreement.site.present?) ],
        "From", [ "#{account.name}, #{branch.name}", branch.address, branch.phone ]

      table(@agreement.lines.includes(:hire_item).map do |line|
        item = line.hire_item
        [ item.name, item.asset_tag, money(line.daily_rate_cents), line.weekly_rate_cents ? money(line.weekly_rate_cents) : "", money(item.deposit_cents) ]
      end)
      total "Deposit", @agreement.deposit_due_cents
      total "Estimated charge to #{time(@agreement.due_back_at)}", @agreement.customer_order.total_cents, size: 9, style: :normal

      pdf.move_down 16
      pdf.text "Terms", size: 10, style: :bold
      TERMS.each.with_index(1) { |term, number| pdf.text "#{number}. #{term}", size: 8, leading: 1 }
      pdf.move_down 30
      signatures
    end

    def signatures
      y = pdf.cursor
      [ [ 0, "Hirer: #{@agreement.customer.name}" ], [ pdf.bounds.width / 2 + 10, "For #{account.name}" ] ].each do |x, label|
        pdf.stroke_line [ x, y ], [ x + pdf.bounds.width / 2 - 20, y ]
        pdf.draw_text label, at: [ x, y - 12 ], size: 8
      end
    end

    def time(value)
      I18n.l(value.in_time_zone(account.time_zone), format: :short)
    end
end
