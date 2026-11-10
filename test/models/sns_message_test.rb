require "test_helper"

class SnsMessageTest < ActiveSupport::TestCase
  KEY = OpenSSL::PKey::RSA.new(2048)
  CERTIFICATE = OpenSSL::X509::Certificate.new.tap do |cert|
    cert.version, cert.serial = 2, 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=sns.amazonaws.com")
    cert.public_key, cert.not_before, cert.not_after = KEY.public_key, Time.current - 1.day, Time.current + 1.year
    cert.sign(KEY, OpenSSL::Digest.new("SHA256"))
  end

  setup { Sns::Message.certificate_fetcher = ->(_url) { CERTIFICATE.to_pem } }
  teardown { Sns::Message.certificate_fetcher = Sns::Message.superclass_attribute_default rescue nil }

  def self.signed(fields, version: "1", key: KEY)
    message = Sns::Message.new(fields.merge("SignatureVersion" => version, "SigningCertURL" => "https://sns.eu-west-1.amazonaws.com/SimpleNotificationService-abc.pem"))
    digest = version == "1" ? OpenSSL::Digest.new("SHA1") : OpenSSL::Digest.new("SHA256")
    message.fields.merge("Signature" => Base64.strict_encode64(key.sign(digest, message.string_to_sign))).to_json
  end

  def self.notification(message, version: "1")
    signed({ "Type" => "Notification", "MessageId" => "m-1", "TopicArn" => "arn:aws:sns:eu-west-1:123:hardpoint-ses-events",
             "Message" => message.to_json, "Timestamp" => "2026-11-08T10:00:00.000Z" }, version: version)
  end

  test "a message signed by Amazon's certificate verifies, with SHA1 or SHA256" do
    assert Sns::Message.parse(self.class.notification({ "hello" => 1 })).verify!.notification?
    assert Sns::Message.parse(self.class.notification({ "hello" => 1 }, version: "2")).verify!
  end

  test "a forged or tampered message is refused" do
    other = OpenSSL::PKey::RSA.new(2048)
    assert_raises(Sns::Message::Invalid) { Sns::Message.parse(self.class.signed({ "Type" => "Notification", "Message" => "x", "MessageId" => "1", "TopicArn" => "a", "Timestamp" => "t" }, key: other)).verify! }

    tampered = JSON.parse(self.class.notification({ "hello" => 1 })).merge("Message" => { "hello" => 2 }.to_json).to_json
    assert_raises(Sns::Message::Invalid) { Sns::Message.parse(tampered).verify! }

    elsewhere = JSON.parse(self.class.notification({ "hello" => 1 })).merge("SigningCertURL" => "https://evil.example.com/cert.pem").to_json
    assert_raises(Sns::Message::Invalid) { Sns::Message.parse(elsewhere).verify! }

    assert_raises(Sns::Message::Invalid) { Sns::Message.parse("not json") }
    assert_raises(Sns::Message::Invalid) { Sns::Message.parse({ "foo" => "bar" }.to_json) }
  end

  test "subscriptions are only confirmed at SNS's own address" do
    message = Sns::Message.new("Type" => "SubscriptionConfirmation", "SubscribeURL" => "https://evil.example.com/confirm")
    assert_raises(Sns::Message::Invalid) { message.confirm_subscription! }
  end
end
