# Any report as a PDF on the shop's letterhead, landscape when it has many columns.
class ReportPdf < DocumentPdf
  def initialize(report)
    @report = report
    super(account: report.account, branch: report.branch)
  end

  def title = @report.title
  def reference = @report.subtitle
  def filename = @report.filename("pdf")

  private
    def page_layout
      @report.sections.map { _1.columns.size }.max.to_i > 6 ? :landscape : :portrait
    end

    def details
      [ "Amounts in #{account.currency}", "Printed #{I18n.l(Time.current, format: :long)}" ]
    end

    def content
      @report.sections.each do |section|
        @section = section
        pdf.start_new_page if pdf.cursor < 120
        if section.title
          pdf.fill_color NAVY
          pdf.text section.title, size: 12, style: :bold
          pdf.move_down 6
        end

        if section.rows.empty?
          note "Nothing in this period."
        else
          row columns.map(&:first), bold: true, fill: CONCRETE
          section.rows.each_with_index do |cells, index|
            if pdf.cursor < 60
              pdf.start_new_page
              row columns.map(&:first), bold: true, fill: CONCRETE
            end
            row formatted(cells), bold: index.in?(section.emphasis)
          end
          row formatted(section.totals), bold: true if section.totals
        end
        pdf.move_down 6
        note section.note if section.note
        pdf.move_down 16
      end
    end

    # Text columns get twice the room of number columns.
    def columns
      weights = @section.columns.map { _1.numeric? ? 1 : 2 }
      unit = pdf.bounds.width / weights.sum
      @section.columns.zip(weights).map { |column, weight| [ column.label, unit * weight ] }
    end

    def alignment(index)
      @section.columns[index].numeric? ? :right : :left
    end

    def formatted(cells)
      cells.zip(@section.columns).map { |value, column| format_cell(value, column) }
    end

    def format_cell(value, column)
      return "" if value.nil?

      case column.type
      when :money then value.is_a?(Numeric) ? money(value) : value.to_s
      when :percent then "#{value.round(1)}%"
      when :quantity then quantity(value)
      when :count then ActiveSupport::NumberHelper.number_to_delimited(value)
      when :date then value.is_a?(Date) ? value.strftime("%-d %b %Y") : value.to_s
      else value.to_s
      end
    end
end
