# HardPoint's own WhatsApp Business number, through Meta's WhatsApp Cloud API: documents and reminders a shop sends
# its customers, each in an approved template naming the shop (docs/WHATSAPP.md has the templates to submit).
#
#   live       WHATSAPP_PHONE_NUMBER_ID and WHATSAPP_ACCESS_TOKEN are set: messages go to Meta
#   simulator  not set, outside production (or with ALLOW_INTEGRATION_SIMULATORS): messages are recorded, not sent
#   off        not set on a live server: nothing can be sent, and Settings says so
module Whatsapp
  GRAPH_URL = "https://graph.facebook.com"

  # Templates as submitted to Meta for approval, with what goes in each placeholder.
  TEMPLATES = {
    "hardpoint_document" => { header: :document, body: %w[ shop document reference amount ] },
    "hardpoint_balance_reminder" => { header: :document, body: %w[ shop customer balance overdue ] }
  }.freeze

  def self.mode
    if ENV["WHATSAPP_PHONE_NUMBER_ID"].present? && ENV["WHATSAPP_ACCESS_TOKEN"].present? then :live
    elsif Mpesa::Shortcode.simulator_allowed? then :simulator
    else :off
    end
  end

  def self.available? = mode != :off
  def self.simulated? = mode == :simulator

  def self.phone_number_id = ENV.fetch("WHATSAPP_PHONE_NUMBER_ID")
  def self.access_token = ENV.fetch("WHATSAPP_ACCESS_TOKEN")
  def self.app_secret = ENV["WHATSAPP_APP_SECRET"]
  def self.verify_token = ENV["WHATSAPP_VERIFY_TOKEN"]
  def self.graph_version = ENV.fetch("WHATSAPP_GRAPH_VERSION", "v21.0")
  def self.language = ENV.fetch("WHATSAPP_TEMPLATE_LANGUAGE", "en")

  # A Kenyan number as WhatsApp wants it: country code, no plus. Nil for anything that isn't a phone number.
  def self.recipient(phone)
    digits = phone.to_s.gsub(/\D/, "")
    digits = "254#{digits.delete_prefix("0")}" if digits.length == 10 && digits.start_with?("0")
    digits = "254#{digits}" if digits.length == 9
    digits if digits.match?(/\A\d{11,15}\z/)
  end
end
