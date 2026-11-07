module ApplicationHelper
  # A link's path tagged with where it was followed from, so UsageTracking can count the shortcut.
  def tracked_path(path, from)
    uri = URI.parse(path)
    uri.query = [ uri.query.presence, { from: from }.to_query ].compact.join("&")
    uri.to_s
  end

  # An inline SVG QR code, e.g. for enrolling an authenticator app.
  def qr_code_svg(text, **svg_attributes)
    RQRCode::QRCode.new(text).as_svg(module_size: 4, use_path: true, viewbox: true, svg_attributes: svg_attributes).html_safe
  end
end
