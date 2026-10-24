# The materials that went into a job, billed to the contractor's own client: on the contractor's
# letterhead (not the shop's, since the prices are theirs), each material at the shop's price plus
# the job's markup. The markup itself isn't printed; it's the contractor's business.
class JobClientBillPdf < DocumentPdf
  COLUMNS = [ [ "Item", 235 ], [ "Quantity", 80 ], [ "Unit price", 95 ], [ "Amount", 105 ] ].freeze

  def initialize(job)
    @job = job
    super(account: job.account, branch: nil)
  end

  def title = "Materials bill"
  def reference = @job.reference || @job.name

  def filename
    "#{@job.customer.name.parameterize}-#{@job.name.parameterize}-materials-bill.pdf"
  end

  private
    def columns = COLUMNS
    def numeric_from = 1

    def details
      [ date(Time.current.in_time_zone(account.time_zone)) ]
    end

    def letterhead
      contractor = @job.customer
      pdf.fill_color NAVY
      pdf.text contractor.name, size: 18, style: :bold
      pdf.fill_color GREY
      pdf.text [ contractor.address, contractor.phone, contractor.email ].compact_blank.join(" · "), size: 9
      pdf.text "PIN #{contractor.tax_pin}", size: 9 if contractor.tax_pin.present?
      pdf.move_up(contractor.tax_pin.present? ? 45 : 34)
      pdf.fill_color ORANGE
      pdf.text title.upcase, size: 16, style: :bold, align: :right
      pdf.fill_color NAVY
      pdf.text reference, size: 12, align: :right
      pdf.fill_color GREY
      details.each { pdf.text _1, size: 9, align: :right }
      pdf.move_down 16
    end

    def content
      two_blocks "Bill to", [ @job.client_name || "—" ], "Job", [ @job.name, @job.site ]

      materials = @job.materials
      rows = materials.map do |material|
        amount = @job.client_cents(material.total_cents)
        [ material.description, "#{quantity(material.quantity)} #{material.unit.abbreviation}", money((amount / material.quantity).round), money(amount) ]
      end
      table(rows.presence || [ [ "No materials yet", "", "", "" ] ])
      total "Total", materials.sum { @job.client_cents(_1.total_cents) }
      pdf.move_down 6
      note "Materials for this job, net of anything returned. Prices include VAT."
    end
end
