module ApplicationHelper
  STATUS_TONES = { success: "bg-green-600", warning: "bg-amber-500", danger: "bg-red-600", neutral: "bg-gray-400",
                   muted: "bg-gray-300", info: "bg-primary-500", dark: "bg-gray-800" }.freeze

  # A status as a small coloured dot before plain text: "● Received". Statuses never get coloured capsules.
  # Tones: success (done, on), warning (needs attention soon), danger (failed, overdue), neutral (in progress),
  # muted (draft, off, cancelled), info, dark.
  def status_dot(label, tone = :neutral, **options)
    muted = tone == :muted
    tag.span(**options, class: class_names("inline-flex items-center gap-1.5 whitespace-nowrap align-middle text-sm font-normal",
      muted ? "text-gray-500" : "text-gray-800", options[:class])) do
      tag.span(class: "size-2 shrink-0 rounded-full #{STATUS_TONES.fetch(tone)}", aria: { hidden: true }) + label
    end
  end

  # How a payment method reads on screen: "M-Pesa", "Airtel Money", "Bank transfer"…
  def payment_method_label(method)
    { "mobile_money" => "M-Pesa", "airtel_money" => "Airtel Money", "on_account" => "On account", "foreign_cash" => "Foreign cash" }
      .fetch(method.to_s) { method.to_s.humanize }
  end

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
