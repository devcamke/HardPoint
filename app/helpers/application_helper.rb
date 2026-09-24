module ApplicationHelper
  # An inline SVG QR code, e.g. for enrolling an authenticator app.
  def qr_code_svg(text, **svg_attributes)
    RQRCode::QRCode.new(text).as_svg(module_size: 4, use_path: true, viewbox: true, svg_attributes: svg_attributes).html_safe
  end
end
