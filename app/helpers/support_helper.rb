module SupportHelper
  # A chat with HardPoint support on WhatsApp, optionally with a first message filled in.
  def whatsapp_support_url(text = nil)
    url = "https://wa.me/#{Rails.configuration.x.support[:whatsapp]}"
    text ? "#{url}?#{{ text: text }.to_query}" : url
  end
end
