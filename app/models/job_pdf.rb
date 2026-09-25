# A job's cost summary: every sale and return tagged to the job, then the materials that went into
# it, for the contractor's records or to pass on to their own client.
class JobPdf < DocumentPdf
  PURCHASE_COLUMNS = [ [ "Date", 90 ], [ "Receipt", 110 ], [ "", 190 ], [ "Amount", 125 ] ].freeze
  MATERIAL_COLUMNS = [ [ "Item", 290 ], [ "Quantity", 100 ], [ "Cost", 125 ] ].freeze

  def initialize(job)
    @job = job
    # On the letterhead of the branch the contractor buys from most recently.
    super(account: job.account, branch: job.completed_sales.order(:completed_at).last&.branch || job.account.branches.order(:id).first)
  end

  def title = "Job cost summary"
  def reference = @job.name

  def filename
    "#{@job.customer.name.parameterize}-#{@job.name.parameterize}-costs.pdf"
  end

  private
    def columns = @columns

    def numeric_from = @columns.size - 1

    def details
      [ ("Their reference #{@job.reference}" if @job.reference), "As at #{date(Time.current.in_time_zone(account.time_zone))}" ]
    end

    def content
      customer = @job.customer
      two_blocks "Customer", [ customer.name, customer.phone, customer.address, ("PIN #{customer.tax_pin}" if customer.tax_pin.present?) ],
        "Job", [ @job.name, @job.site, ("Budget #{Money.format(@job.budget_cents, currency: account.currency)}" if @job.budget_cents) ]

      @columns = PURCHASE_COLUMNS
      table(purchases)
      total "Total", @job.spent_cents
      if @job.budget_cents
        left = @job.budget_left_cents
        total left.negative? ? "Over budget" : "Budget left", left.abs, size: 10, style: :normal
      end

      materials = @job.materials
      return if materials.empty?

      pdf.move_down 16
      pdf.fill_color NAVY
      pdf.text "Materials", size: 11, style: :bold
      pdf.move_down 4
      @columns = MATERIAL_COLUMNS
      table(materials.map { [ _1.description, "#{quantity(_1.quantity)} #{_1.unit.abbreviation}", money(_1.total_cents) ] })
      note "Prices include tax. Quantities are net of returns."
    end

    def purchases
      zone = account.time_zone
      sales = @job.completed_sales.includes(:branch).map { [ _1.completed_at, _1.receipt_number, "Purchase", _1.total_cents ] }
      returns = @job.returns.includes(:branch, sale: :branch).map { [ _1.created_at, _1.return_number, "Return from #{_1.sale.receipt_number}", -_1.total_cents ] }
      (sales + returns).sort_by(&:first).map { |at, number, what, cents| [ at.in_time_zone(zone).strftime("%-d %b %Y"), number, what, money(cents) ] }
    end
end
