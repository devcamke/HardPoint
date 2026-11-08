require "net/http"

# A message from Amazon SNS to an HTTPS endpoint (the SES bounce and complaint notifications), checked the way
# AWS says to before anything in it is believed: the signing certificate must come from an amazonaws.com SNS
# address over HTTPS, and the signature (SHA1 or SHA256 with RSA, by SignatureVersion) must verify over the
# message's fields in the documented order. A message that doesn't verify is refused.
class Sns::Message
  Invalid = Class.new(StandardError)

  CERTIFICATE_HOST = /\Asns\.[a-z0-9-]+\.amazonaws\.com(\.cn)?\z/
  NOTIFICATION_FIELDS = %w[ Message MessageId Subject Timestamp TopicArn Type ].freeze
  CONFIRMATION_FIELDS = %w[ Message MessageId SubscribeURL Timestamp Token TopicArn Type ].freeze

  # How the signing certificate is fetched (a URL → PEM); tests hand over a certificate of their own.
  class_attribute :certificate_fetcher, default: ->(url) { Net::HTTP.get_response(URI(url)).then { _1.is_a?(Net::HTTPSuccess) ? _1.body : raise(Invalid, "certificate #{_1.code}") } }

  attr_reader :fields

  def self.parse(raw)
    fields = JSON.parse(raw)
    raise Invalid, "not an SNS message" unless fields.is_a?(Hash) && fields["Type"].present?

    new(fields)
  rescue JSON::ParserError
    raise Invalid, "not JSON"
  end

  def initialize(fields)
    @fields = fields
  end

  def type = fields["Type"]
  def topic_arn = fields["TopicArn"]
  def message = fields["Message"]
  def subscribe_url = fields["SubscribeURL"]
  def notification? = type == "Notification"
  def subscription_confirmation? = type == "SubscriptionConfirmation"

  def verify!
    certificate = OpenSSL::X509::Certificate.new(certificate_pem)
    digest = case fields["SignatureVersion"].to_s
    when "1" then OpenSSL::Digest.new("SHA1")
    when "2" then OpenSSL::Digest.new("SHA256")
    else raise Invalid, "unknown signature version #{fields["SignatureVersion"]}"
    end
    raise Invalid, "bad signature" unless certificate.public_key.verify(digest, Base64.decode64(fields["Signature"].to_s), string_to_sign)

    self
  rescue OpenSSL::OpenSSLError => error
    raise Invalid, error.message
  end

  # The URL SNS gives for confirming a subscription must itself be SNS's, or confirming would be a request to anywhere.
  def confirm_subscription!
    uri = URI(subscribe_url.to_s)
    raise Invalid, "subscribe URL isn't SNS's" unless uri.scheme == "https" && uri.host.to_s.match?(CERTIFICATE_HOST)

    Net::HTTP.get_response(uri)
  end

  def string_to_sign
    names = notification? ? NOTIFICATION_FIELDS : CONFIRMATION_FIELDS
    names.filter_map { |name| "#{name}\n#{fields[name]}\n" if fields.key?(name) }.join
  end

  private
    def certificate_pem
      uri = URI(fields["SigningCertURL"].to_s)
      raise Invalid, "certificate URL isn't SNS's" unless uri.scheme == "https" && uri.host.to_s.match?(CERTIFICATE_HOST) && uri.path.end_with?(".pem")

      Rails.cache.fetch("sns-certificate:#{uri}", expires_in: 1.day) { certificate_fetcher.call(uri.to_s) }
    end
end
