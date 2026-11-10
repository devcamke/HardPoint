# Charts and figures for the owner's emails, drawn as tables with inline styles: mail apps strip scripts and most
# SVG, but every one of them lays out a table. One hue (the brand teal) carries every bar; the darkest step marks the
# day or week the email is about. Status colours (short, over, balanced) always come with a symbol and a word.
module MailChartsHelper
  MAIL_COLORS = {
    ink: "#111827", secondary: "#4B5563", muted: "#6B7280", rule: "#E5E7EB", panel: "#F4F7F7",
    bar: "#0F5E6E", bar_soft: "#A9C8CE",
    critical: "#C62F2F", warning: "#B7791F", good: "#15803D"
  }.freeze
  # Light to dark in the one hue, for buckets in order (how late a debt is).
  MAIL_RAMP = %w[ #C3D7DB #93B7BE #4B8692 #0F5E6E #072D35 ].freeze
  STATUS_MARKS = { critical: "▼", warning: "▲", good: "✓" }.freeze

  def mail_color(name) = MAIL_COLORS.fetch(name)

  # A heading for one part of the email, with an optional line under it.
  def mail_section(title, note = nil)
    heading = tag.h2(title, style: "margin:32px 0 2px; font-size:17px; line-height:1.3; font-weight:700; color:#{mail_color(:ink)};")
    note ? heading + tag.p(note, style: "margin:0 0 12px; font-size:13px; color:#{mail_color(:muted)};") : heading + tag.div(style: "height:10px;")
  end

  # A symbol and word in ink, the symbol in the status colour: never colour alone.
  def mail_status(tone, text)
    safe_join([ tag.span(STATUS_MARKS.fetch(tone), style: "color:#{mail_color(tone)}; font-size:11px;"), " ", text ])
  end

  # Small figures side by side: [ [ label, value, note ], ... ].
  def mail_tiles(tiles)
    cells = tiles.map do |label, value, note|
      tag.td(class: "mail-tile", style: "width:#{100 / tiles.size}%; padding:12px 14px; background:#{mail_color(:panel)}; border-radius:8px; vertical-align:top;") do
        safe_join([
          tag.div(label, style: "font-size:12px; color:#{mail_color(:muted)};"),
          tag.div(value, style: "font-size:19px; font-weight:700; color:#{mail_color(:ink)}; white-space:nowrap;"),
          (tag.div(note, style: "font-size:12px; color:#{mail_color(:secondary)};") if note)
        ].compact)
      end
    end
    spaced = cells.flat_map { [ _1, tag.td(class: "mail-tile-gap", style: "width:8px;") ] }[0...-1]
    mail_table { tag.tr(safe_join(spaced)) }
  end

  # Upright bars for values in order (hours, days, weeks): [ [ label, value ], ... ]. The highlighted bar is dark and
  # the others light; only the highlighted bar and the tallest are labelled with their value.
  def mail_column_chart(points, highlight: nil, height: 110, format: ->(value) { value.to_s }, label_every: 1, caption: nil)
    return "".html_safe if points.empty?

    peak = points.map(&:last).max.to_f
    labelled = [ highlight, points.max_by(&:last)&.first ].compact
    bars = points.map do |label, value|
      bar_height = peak.positive? ? [ (value / peak * height).round, value.positive? ? 3 : 0 ].max : 0
      text = labelled.include?(label) && value.positive? ? tag.div(format.(value), style: "font-size:10px; line-height:12px; color:#{mail_color(:secondary)}; white-space:nowrap; padding-bottom:3px;") : nil
      bar = bar_height.positive? ? tag.div("&nbsp;".html_safe, style: "height:#{bar_height}px; background:#{label == highlight ? mail_color(:bar) : mail_color(:bar_soft)}; border-radius:4px 4px 0 0; font-size:0; line-height:0;") : nil
      tag.td(safe_join([ text, bar ].compact), align: "center", valign: "bottom", style: "height:#{height + 16}px; padding:0 2px; vertical-align:bottom;")
    end
    labels = points.each_with_index.map do |(label, _), index|
      tag.td((index % label_every).zero? ? label : "", align: "center",
        style: "padding-top:5px; font-size:10px; color:#{label == highlight ? mail_color(:ink) : mail_color(:muted)}; #{"font-weight:700;" if label == highlight} white-space:nowrap;")
    end
    chart = mail_table(style: "table-layout:fixed;") do
      safe_join([ tag.tr(safe_join(bars)), tag.tr(tag.td(style: "border-top:1px solid #{mail_color(:rule)}; font-size:0; line-height:0;", colspan: points.size)), tag.tr(safe_join(labels)) ])
    end
    caption ? chart + tag.p(caption, style: "margin:6px 0 0; font-size:12px; color:#{mail_color(:muted)};") : chart
  end

  # Bars across, one row each: [ [ label, value, value text, (note) ], ... ], longest first as given. `colors` gives
  # each row its own step (a ramp for buckets in order); otherwise every bar is the brand teal.
  def mail_bar_rows(rows, colors: nil, label_width: 40)
    return "".html_safe if rows.empty?

    peak = rows.map { _1[1] }.max.to_f
    mail_table do
      safe_join(rows.each_with_index.map do |(label, value, value_text, note), index|
        percent = peak.positive? ? (value / peak * 100).round.clamp(value.positive? ? 2 : 0, 100) : 0
        color = colors ? colors[index] : mail_color(:bar)
        bar = mail_table do
          tag.tr(safe_join([
            (tag.td("&nbsp;".html_safe, width: "#{percent}%", style: "background:#{color}; height:10px; border-radius:0 4px 4px 0; font-size:0; line-height:0;") if percent.positive?),
            (tag.td("&nbsp;".html_safe, style: "font-size:0; line-height:0;") if percent < 100)
          ].compact))
        end
        label_cell = safe_join([ label, (tag.div(note, style: "font-size:11px; color:#{mail_color(:muted)};") if note) ].compact)
        tag.tr(safe_join([
          tag.td(label_cell, width: "#{label_width}%", style: "padding:6px 10px 6px 0; font-size:13px; color:#{mail_color(:ink)}; vertical-align:middle;"),
          tag.td(bar, width: "#{100 - label_width - 22}%", style: "padding:6px 0; vertical-align:middle;"),
          tag.td(value_text, align: "right", width: "22%", style: "padding:6px 0 6px 10px; font-size:13px; color:#{mail_color(:ink)}; white-space:nowrap; vertical-align:middle; font-variant-numeric:tabular-nums;")
        ]))
      end)
    end
  end

  # A short gauge: how much of the reorder level is left on the shelf (empty at zero or below).
  def mail_meter(fraction, width: 72)
    filled = (fraction.to_f.clamp(0, 1) * width).round
    color = fraction.to_f <= 0 ? mail_color(:critical) : mail_color(:bar)
    tag.table(role: "presentation", cellspacing: 0, cellpadding: 0, border: 0, style: "border-collapse:collapse; width:#{width}px; display:inline-table; vertical-align:middle;") do
      tag.tr(safe_join([
        (tag.td("&nbsp;".html_safe, style: "width:#{filled}px; height:8px; background:#{color}; border-radius:4px 0 0 4px; font-size:0; line-height:0;") if filled.positive?),
        tag.td("&nbsp;".html_safe, style: "height:8px; background:#{filled.positive? ? "#E3ECEE" : "#F3D6D6"}; border-radius:#{filled.positive? ? "0 4px 4px 0" : "4px"}; font-size:0; line-height:0;")
      ].compact))
    end
  end

  # A plain table: [ headers ], [ [ cells ] ]; numbers right-aligned by passing align: [ :left, :right, ... ].
  def mail_list(headers, rows, align: [])
    return "".html_safe if rows.empty?

    head = tag.tr(safe_join(headers.each_with_index.map { |header, index|
      tag.th(header, align: (align[index] || :left).to_s, style: "padding:0 0 6px; font-size:11px; font-weight:600; text-transform:uppercase; letter-spacing:.04em; color:#{mail_color(:muted)};")
    }))
    body = rows.map do |cells|
      tag.tr(safe_join(cells.each_with_index.map { |cell, index|
        tag.td(cell, align: (align[index] || :left).to_s, style: "padding:7px #{index == cells.size - 1 ? 0 : 10}px 7px 0; border-top:1px solid #{mail_color(:rule)}; font-size:13px; color:#{mail_color(:ink)}; vertical-align:top;#{" white-space:nowrap;" if align[index] == :right}")
      }))
    end
    mail_table { safe_join([ head, *body ]) }
  end

  # A soft panel holding a few lines that need attention.
  def mail_callout(&)
    mail_table { tag.tr(tag.td(capture(&), style: "padding:12px 14px; background:#FDF6F6; border-left:3px solid #{mail_color(:critical)}; border-radius:0 6px 6px 0; font-size:13px; color:#{mail_color(:ink)};")) }
  end

  def mail_button(text, url)
    link_to text, url, style: "display:inline-block; background:#{mail_color(:bar)}; color:#FFFFFF; text-decoration:none; font-weight:600; font-size:14px; padding:10px 18px; border-radius:6px;"
  end

  # "▲ 12% on last Monday" in the right tone, or nothing without a comparison.
  def mail_change(percent, against)
    return if percent.nil?

    tone = percent.negative? ? :critical : :good
    mark = percent.negative? ? "▼" : "▲"
    safe_join([ tag.span(mark, style: "color:#{mail_color(tone)};"), " #{percent.abs}% #{percent.negative? ? "down" : "up"} on #{against}" ])
  end

  # "7am", "12pm", "6pm": hours on a chart.
  def mail_hour(hour) = "#{hour % 12 == 0 ? 12 : hour % 12}#{hour < 12 ? "am" : "pm"}"

  # "12k" for chart labels, where the full amount would crowd the bars.
  def mail_short_money(cents)
    whole = cents.to_i / 100
    if whole >= 1_000_000 then "#{(whole / 1_000_000.0).round(1).to_s.delete_suffix(".0")}m"
    elsif whole >= 1_000 then "#{(whole / 1_000.0).round(whole >= 100_000 ? 0 : 1).to_s.delete_suffix(".0")}k"
    else whole.to_s
    end
  end

  private
    def mail_table(style: "", &)
      tag.table(capture(&), role: "presentation", width: "100%", cellspacing: 0, cellpadding: 0, border: 0, style: "border-collapse:collapse; #{style}")
    end
end
