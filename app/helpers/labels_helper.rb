require "barby/barcode/ean_13"
require "barby/barcode/code_128"
require "barby/outputter/svg_outputter"

module LabelsHelper
  # EAN-13 when the code is a valid one (what most scanners expect on retail goods), Code 128 otherwise.
  def barcode_svg(code)
    barcode = if code.match?(/\A\d{13}\z/) && Product.ean13_check_digit(code[0, 12]) == code[-1].to_i
      Barby::EAN13.new(code[0, 12])
    else
      Barby::Code128B.new(code)
    end

    barcode.to_svg(height: 40, xdim: 2, margin: 0).sub(/\A<\?xml[^>]*>\s*/, "")
      .sub("<svg ", %(<svg preserveAspectRatio="none" class="barcode" role="img" aria-label="Barcode #{ERB::Util.html_escape(code)}" )).html_safe
  end
end
