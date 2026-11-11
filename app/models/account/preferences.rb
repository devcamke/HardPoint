# The owner's choices that tune HardPoint to their shop, kept in accounts.preferences and read through typed methods
# that fall back to HardPoint's defaults. Adding one is a line in PREFERENCES and a field on the Preferences page.
module Account::Preferences
  extend ActiveSupport::Concern

  Preference = Data.define(:key, :type, :default, :range) do
    def initialize(key:, type:, default:, range: nil) = super
  end

  # Payment buttons the till can show; cash is always there. Deposits and foreign notes appear by themselves when
  # they apply, so they aren't listed.
  TILL_TENDERS = { "mobile_money" => "M-Pesa", "airtel_money" => "Airtel Money", "card" => "Card", "on_account" => "On account" }.freeze

  PREFERENCES = [
    # Look
    Preference.new(key: "theme_color", type: :color, default: Theme::PRESETS.fetch(Theme::DEFAULT).color),
    Preference.new(key: "receipt_stamp", type: :boolean, default: true),
    # Selling
    Preference.new(key: "quote_validity_days", type: :integer, default: 14, range: 1..365),
    Preference.new(key: "customer_payment_terms_days", type: :integer, default: 30, range: 0..365),
    Preference.new(key: "till_tenders", type: :list, default: TILL_TENDERS.keys),
    # Stock promised to confirmed orders: the till warns before selling it to someone else, or holds it (refuses).
    Preference.new(key: "order_stock", type: :choice, default: "warn", range: %w[ warn hold ]),
    # Credit control: an account with an invoice more than this many days overdue takes nothing more on account
    # without a manager's PIN (0: never held); and who's reminded each Monday of what's overdue.
    Preference.new(key: "credit_hold_after_days", type: :integer, default: 0, range: 0..365),
    Preference.new(key: "weekly_reminders", type: :choice, default: "off", range: %w[ off sms whatsapp ]),
    # Stock
    Preference.new(key: "expiry_warning_days", type: :integer, default: 30, range: 1..365),
    Preference.new(key: "dead_stock_days", type: :integer, default: 90, range: 14..730),
    Preference.new(key: "reorder_lookback_days", type: :integer, default: 30, range: 7..365),
    Preference.new(key: "supplier_lead_time_days", type: :integer, default: 7, range: 0..180),
    # Documents
    Preference.new(key: "document_terms", type: :text, default: nil, range: 0..1000),
    Preference.new(key: "payment_details", type: :text, default: nil, range: 0..500)
  ].index_by(&:key).freeze

  included do
    has_one_attached :logo
    validate :preferences_are_valid, if: :preferences_changed?
    validate :logo_is_an_image, if: -> { attachment_changes["logo"].present? }
  end

  PREFERENCES.each_value do |preference|
    define_method(preference.key) { read_preference(preference) }
    define_method(:"#{preference.key}=") { |value| write_preference(preference, value) }
  end

  def theme = Theme.new(theme_color)

  def quote_validity = quote_validity_days.days
  def expiry_warning = expiry_warning_days.days

  def hold_order_stock? = order_stock == "hold"

  def till_tender?(tender) = tender.to_s == "cash" || tender.to_s.in?(till_tenders)

  private
    def read_preference(preference)
      value = (preferences || {})[preference.key]
      return preference.default if value.nil?

      case preference.type
      when :integer then value.to_i
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      when :list then Array(value) & TILL_TENDERS.keys
      when :choice then value.to_s.in?(preference.range) ? value.to_s : preference.default
      else value
      end
    end

    def write_preference(preference, value)
      self.preferences = (preferences || {}).merge(preference.key => cast_preference(preference, value))
    end

    def cast_preference(preference, value)
      case preference.type
      when :integer then value.presence && Integer(value.to_s, exception: false) || value.to_s
      when :boolean then ActiveModel::Type::Boolean.new.cast(value)
      when :list then Array(value).map(&:to_s).compact_blank & TILL_TENDERS.keys
      when :color then Theme.normalize(value) || value.to_s
      when :text then value.to_s.strip.presence
      when :choice then value.to_s
      end
    end

    def preferences_are_valid
      PREFERENCES.each_value do |preference|
        value = (preferences || {})[preference.key]
        next if value.nil?

        case preference.type
        when :integer
          errors.add preference.key, "must be a whole number from #{preference.range.min} to #{preference.range.max}" unless value.is_a?(Integer) && preference.range.cover?(value)
        when :color
          if !Theme.normalize(value)
            errors.add :theme_color, "must be a colour like #0F5E6E"
          elsif !Theme.readable?(value)
            errors.add :theme_color, "is too light: white writing on it would be hard to read (contrast #{Theme.contrast_with_white(value)}:1, at least #{Theme::MIN_CONTRAST}:1 needed). Choose a darker shade"
          end
        when :choice
          errors.add preference.key, "must be one of #{preference.range.to_sentence(last_word_connector: " or ")}" unless value.in?(preference.range)
        when :text
          errors.add preference.key, "is too long (at most #{preference.range.max} characters)" if value.to_s.length > preference.range.max
        end
      end
    end

    def logo_is_an_image
      if !logo.content_type.in?(%w[ image/png image/jpeg image/webp ])
        errors.add :logo, "must be a PNG, JPEG or WebP picture"
      elsif logo.blob.byte_size > 1.megabyte
        errors.add :logo, "must be under 1 MB"
      end
    end
end
