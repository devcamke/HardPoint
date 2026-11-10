# A shop's colour theme: one of the presets, or its own colour. The app's primary colour (top bar, buttons, links,
# active tabs) is drawn as ten shades from it, worked out here in OKLab so each step looks evenly lighter or darker,
# and written as plain hex: every till's browser shows it, however old. A colour that white text can't be read on
# isn't accepted.
class Theme
  Preset = Data.define(:key, :name, :color)

  PRESETS = [
    Preset.new("teal", "Petrol teal", "#0F5E6E"),
    Preset.new("blue", "Ocean blue", "#1D4ED8"),
    Preset.new("green", "Forest green", "#166534"),
    Preset.new("red", "Brick red", "#B91C1C"),
    Preset.new("orange", "Burnt orange", "#C2410C"),
    Preset.new("purple", "Royal purple", "#6D28D9"),
    Preset.new("charcoal", "Charcoal", "#334155"),
    Preset.new("brown", "Earth brown", "#7C4A1E")
  ].index_by(&:key).freeze

  DEFAULT = "teal"
  HEX = /\A#\h{6}\z/
  # White text on the colour must reach WCAG AA for normal text.
  MIN_CONTRAST = 4.5

  # How far each shade is mixed towards white (below 500) or black (above it).
  LIGHTER = { 50 => 0.94, 100 => 0.86, 200 => 0.70, 300 => 0.50, 400 => 0.26 }.freeze
  DARKER = { 600 => 0.12, 700 => 0.24, 800 => 0.38, 900 => 0.52 }.freeze

  attr_reader :color

  def self.for(account)
    new(account.theme_color)
  end

  def initialize(color)
    @color = self.class.normalize(color) || PRESETS.fetch(DEFAULT).color
  end

  def self.normalize(color)
    color = color.to_s.strip.upcase
    color = "##{color}" if color.match?(/\A\h{6}\z/)
    color if color.match?(HEX)
  end

  def self.readable?(color) = contrast_with_white(color) >= MIN_CONTRAST

  def default? = color == PRESETS.fetch(DEFAULT).color

  def preset = PRESETS.values.find { _1.color == color }

  # { 50 => "#F3F7F8", …, 500 => color, …, 900 => "#…" }
  def shades
    @shades ||= LIGHTER.transform_values { mix(color, "#FFFFFF", _1) }
      .merge(500 => color).merge(DARKER.transform_values { mix(color, "#000000", _1) }).sort.to_h
  end

  # CSS that repaints the app in this theme, overriding Tailwind's colour variables. Nothing for the default, whose
  # shades were picked by hand in app/assets/tailwind/application.css.
  def css
    return "" if default?

    variables = shades.map { |step, hex| "--color-primary-#{step}: #{hex};" }
    variables += [ "--color-accent-500: #{shades[400]};", "--color-accent-600: #{shades[600]};", "--color-accent-700: #{shades[700]};" ]
    ":root { #{variables.join(" ")} }"
  end

  def self.contrast_with_white(color)
    luminance = relative_luminance(normalize(color) || "#FFFFFF")
    (1.05 / (luminance + 0.05)).round(2)
  end

  def self.relative_luminance(hex)
    r, g, b = rgb(hex).map { |channel| channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  def self.rgb(hex) = hex.delete("#").scan(/../).map { _1.to_i(16) / 255.0 }

  private
    # Mixed in OKLab, a share of the way from `from` to `to`.
    def mix(from, to, share)
      a, b = oklab(from), oklab(to)
      to_hex(a.zip(b).map { |x, y| x + (y - x) * share })
    end

    def oklab(hex)
      r, g, b = self.class.rgb(hex).map { |c| c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
      l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
      m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
      s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
      [ 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s ]
    end

    def to_hex(lab)
      l, a, b = lab
      l_, m_, s_ = [ l + 0.3963377774 * a + 0.2158037573 * b, l - 0.1055613458 * a - 0.0638541728 * b, l - 0.0894841775 * a - 1.2914855480 * b ].map { _1**3 }
      rgb = [ 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
              -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
              -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_ ]
      "#" + rgb.map { |c| c = c.clamp(0.0, 1.0); c = c <= 0.0031308 ? 12.92 * c : 1.055 * c**(1 / 2.4) - 0.055; (c * 255).round.clamp(0, 255).to_s(16).rjust(2, "0") }.join.upcase
    end
end
