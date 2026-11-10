# Action Mailer's delivery method for the SES API: the whole message, as built, through SendEmail, under the
# configuration set whose SNS topic brings bounces and complaints back. Tagged with the mailer that sent it,
# so SES's own statistics can be read per kind of email. Registered as :ses in config/initializers/ses.rb.
class Ses::Delivery
  attr_reader :settings

  def initialize(settings = {})
    @settings = settings
  end

  def deliver!(mail)
    response = Ses.client.send_email(
      from_email_address: mail.smtp_envelope_from,
      destination: { to_addresses: mail.smtp_envelope_to },
      content: { raw: { data: mail.encoded } },
      configuration_set_name: Ses.configuration_set,
      email_tags: tags_for(mail)
    )
    mail.message_id = "#{response.message_id}@#{Ses.region}.amazonses.com"
    response
  end

  private
    # SES tag names and values: letters, digits, _ and -, up to 256 characters.
    def tags_for(mail)
      mailer = mail.header["X-HardPoint-Mailer"]&.value.to_s.gsub(/[^A-Za-z0-9_-]/, "_").first(200)
      mailer.present? ? [ { name: "mailer", value: mailer } ] : []
    end
end
