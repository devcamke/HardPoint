# Optional parts of HardPoint a shop switches on in Settings › Features. A feature that's off is left
# out of the menus, Settings, Home and forms; its records are kept, so switching it back on brings
# everything back. A feature can't be switched off while it's live (a promotion running, products
# recording batches), so switching one off never quietly changes what the till does.
module Account::Features
  extend ActiveSupport::Concern

  Feature = Data.define(:key, :name, :description, :group)

  FEATURES = [
    Feature.new("deliveries", "Deliveries", "Delivery notes, dispatch and proof of delivery", "Selling"),
    Feature.new("promotions", "Promotions", "Percent off, buy 10 get 1 free, any 3 for a price", "Selling"),
    Feature.new("currencies", "Foreign currencies", "Dollars and other notes at the till, and suppliers who invoice in them", "Selling"),
    Feature.new("online_store", "Online store", "Click-and-collect from your own web address", "Selling"),
    Feature.new("whatsapp_messages", "WhatsApp from HardPoint", "Send receipts, quotes, credit notes, statements and balance reminders from HardPoint's WhatsApp number, and see when they're read", "Selling"),
    Feature.new("fundis", "Fundi commissions", "Pay masons, plumbers and electricians a commission on the customers they bring", "Selling"),
    Feature.new("jobs", "Contractor jobs", "Tag a contractor's purchases to a project and track it against a budget", "Stock and work"),
    Feature.new("batches", "Batches and expiry dates", "For paint, adhesives and chemicals: first-expiring-first selling and recalls", "Stock and work"),
    Feature.new("serial_numbers", "Serial numbers", "Record the serial number of each power tool or generator sold", "Stock and work"),
    Feature.new("developers", "API and webhooks", "Connect a web shop, accounting package or other apps", "Stock and work")
  ].freeze

  KEYS = FEATURES.map(&:key).freeze

  # What a new shop starts with (the column's default); the rest are a switch away.
  DEFAULTS = %w[ deliveries ].freeze

  included do
    before_validation { self.features = (features || []).map(&:to_s).select { _1.in?(KEYS) }.uniq.sort }
    validate :switched_off_features_are_not_in_use, if: :features_changed?
  end

  def feature?(key)
    features.include?(key.to_s)
  end

  # Features this shop has records for, which an existing shop keeps switched on.
  def features_in_use
    KEYS.select { |key| in_use?(key) }
  end

  # Why a feature can't be switched off right now, or nil if it can.
  def feature_in_use_reason(key)
    case key.to_s
    when "promotions"
      count = promotions.running.count
      "#{count == 1 ? "A promotion is" : "#{count} promotions are"} running. End #{count == 1 ? "it" : "them"} first." if count.positive?
    when "currencies"
      "Foreign notes are taken at the till. Stop taking them in Currencies first." if currencies.at_till.exists?
    when "online_store"
      "Your online store is open. Close it first." if storefront&.enabled?
    when "batches"
      count = products.where(tracks_batches: true).count
      "#{count == 1 ? "A product records" : "#{count} products record"} batches. Untick that on #{count == 1 ? "it" : "them"} first." if count.positive?
    when "serial_numbers"
      count = products.where(serialized: true).count
      "#{count == 1 ? "A product records" : "#{count} products record"} serial numbers. Untick that on #{count == 1 ? "it" : "them"} first." if count.positive?
    when "fundis"
      owed = fundi_entries.sum(:amount_cents)
      "Fundis are owed #{Money.format(owed)} in commission. Pay it first." if owed.positive?
    when "developers"
      count = api_keys.active.count
      "#{count == 1 ? "An API key is" : "#{count} API keys are"} still active. Revoke #{count == 1 ? "it" : "them"} first." if count.positive?
    end
  end

  private
    def in_use?(key)
      case key
      when "deliveries" then delivery_notes.exists?
      when "promotions" then promotions.exists?
      when "currencies" then currencies.exists?
      when "online_store" then storefront.present?
      when "jobs" then jobs.exists?
      when "fundis" then fundis.exists?
      when "whatsapp_messages" then whatsapp_messages.exists?
      when "batches" then stock_batches.exists? || products.where(tracks_batches: true).exists?
      when "serial_numbers" then products.where(serialized: true).exists?
      when "developers" then api_keys.exists? || webhook_endpoints.exists?
      end
    end

    def switched_off_features_are_not_in_use
      (Array(features_was) - features).each do |key|
        if (reason = feature_in_use_reason(key))
          errors.add :base, "#{FEATURES.find { _1.key == key }.name} can't be switched off: #{reason}"
        end
      end
    end
end
