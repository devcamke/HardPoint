module ReportsHelper
  def report_cell(value, column)
    return if value.nil?

    case column.type
    when :money then value.is_a?(Numeric) ? report_amount(value) : value
    when :percent then "#{number_with_precision(value, precision: 1)}%"
    when :quantity then quantity(value)
    when :count then number_with_delimiter(value)
    when :date then value.is_a?(Date) ? l(value, format: :long) : value
    when :link then value.is_a?(Report::Link) ? link_to(value.text, value.record, class: "hover:text-safety-700") : value
    else value
    end
  end

  # Amounts in report tables go without the currency, which the page states once.
  def report_amount(cents)
    number_with_precision(cents / 100.0, precision: 2, delimiter: ",")
  end

  def report_cell_classes(value, column)
    class_names("tabular-nums text-right whitespace-nowrap" => column.numeric?, "text-red-700" => value.is_a?(Numeric) && value.negative? && column.type == :money)
  end

  def report_path_with(report, **changes)
    report_path(report.class.key, request.query_parameters.merge(changes.transform_keys(&:to_s)))
  end
end
