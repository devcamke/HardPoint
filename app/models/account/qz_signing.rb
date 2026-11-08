# QZ Tray prints a till's receipts without asking at each one when the site signs its print requests with a
# key QZ Tray trusts. Each shop has its own key and certificate, made the first time one of its tills asks, so a
# signature from one shop means nothing to another shop's tills. When the platform has a certificate issued by
# QZ (credentials qz: { certificate:, private_key: }), the shop's certificate is issued under it and QZ Tray
# trusts it with no prompt at all; without one, the shop's certificate is self-signed and QZ Tray asks the
# cashier once per till to remember it.
module Account::QzSigning
  extend ActiveSupport::Concern

  CERTIFICATE_YEARS = 10
  # QZ Tray reads an issuing certificate appended after this marker.
  INTERMEDIATE_MARKER = "--START INTERMEDIATE CERT--"

  included do
    encrypts :qz_private_key
  end

  # What the till gives QZ Tray: the shop's certificate, and the platform's after it when it issued the shop's.
  def qz_certificate_chain
    ensure_qz_keys!
    [ qz_certificate.strip, (self.class.qz_platform_keys[:certificate].to_s.strip.presence&.then { "#{INTERMEDIATE_MARKER}\n#{_1}" }) ].compact.join("\n")
  end

  # Signs a QZ Tray request (SHA-512 with RSA), base64 as QZ Tray expects.
  def qz_sign(data)
    ensure_qz_keys!
    Base64.strict_encode64 OpenSSL::PKey::RSA.new(qz_private_key).sign(OpenSSL::Digest.new("SHA512"), data.to_s)
  end

  def qz_public_key
    ensure_qz_keys!
    OpenSSL::X509::Certificate.new(qz_certificate).public_key
  end

  class_methods do
    # The platform's QZ-issued certificate and key, if it has them (config.x.qz in tests).
    def qz_platform_keys
      Rails.configuration.x.qz.presence || Rails.application.credentials.qz || {}
    end
  end

  private
    def ensure_qz_keys!
      return if qz_certificate.present?

      with_lock do
        next if qz_certificate.present?

        key = OpenSSL::PKey::RSA.new(2048)
        update!(qz_private_key: key.to_pem, qz_certificate: build_qz_certificate(key).to_pem)
      end
    end

    def build_qz_certificate(key)
      issuer_pem, issuer_key_pem = self.class.qz_platform_keys.values_at(:certificate, :private_key)
      issuer = OpenSSL::X509::Certificate.new(issuer_pem) if issuer_pem.present? && issuer_key_pem.present?

      certificate = OpenSSL::X509::Certificate.new
      certificate.version = 2
      certificate.serial = OpenSSL::BN.new(SecureRandom.hex(16), 16)
      certificate.subject = OpenSSL::X509::Name.new([ [ "CN", "#{subdomain}.#{Rails.configuration.x.webhook_url_options[:host]}" ], [ "O", name.to_s.first(64) ] ])
      certificate.issuer = issuer ? issuer.subject : certificate.subject
      certificate.public_key = key.public_key
      certificate.not_before = Time.current - 1.day
      certificate.not_after = Time.current + CERTIFICATE_YEARS.years

      extensions = OpenSSL::X509::ExtensionFactory.new(issuer || certificate, certificate)
      certificate.add_extension extensions.create_extension("basicConstraints", "CA:FALSE", true)
      certificate.add_extension extensions.create_extension("keyUsage", "digitalSignature", true)
      certificate.add_extension extensions.create_extension("subjectKeyIdentifier", "hash")
      certificate.sign(issuer ? OpenSSL::PKey::RSA.new(issuer_key_pem) : key, OpenSSL::Digest.new("SHA256"))
    end
end
