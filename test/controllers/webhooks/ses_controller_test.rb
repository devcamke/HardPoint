require "test_helper"
require_relative "../../models/sns_message_test"

class Webhooks::SesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Sns::Message.certificate_fetcher = ->(_url) { SnsMessageTest::CERTIFICATE.to_pem }
    use_apex_domain
  end

  def post_event(**event)
    post ses_webhook_path, params: SnsMessageTest.notification(event.transform_keys(&:to_s)), headers: { "Content-Type" => "text/plain" }
  end

  test "a permanent bounce and a complaint stop us emailing those addresses" do
    post_event("eventType" => "Bounce", "bounce" => { "bounceType" => "Permanent", "bounceSubType" => "General",
      "bouncedRecipients" => [ { "emailAddress" => "gone@example.com", "diagnosticCode" => "smtp; 550 user unknown" } ] },
      "mail" => { "timestamp" => "2026-11-08T09:59:00.000Z", "destination" => [ "gone@example.com" ] })
    assert_response :success
    suppression = EmailSuppression.for("gone@example.com")
    assert_equal [ "bounce", "General: smtp; 550 user unknown" ], [ suppression.reason, suppression.detail ]
    assert_equal Time.utc(2026, 11, 8, 9, 59), suppression.event_at

    post_event("notificationType" => "Complaint", "complaint" => { "complaintFeedbackType" => "abuse", "complainedRecipients" => [ { "emailAddress" => "angry@example.com" } ] }, "mail" => {})
    assert_response :success
    assert_equal "complaint", EmailSuppression.for("angry@example.com").reason

    post_event("eventType" => "Bounce", "bounce" => { "bounceType" => "Transient", "bounceSubType" => "MailboxFull", "bouncedRecipients" => [ { "emailAddress" => "full@example.com" } ] }, "mail" => {})
    assert_not EmailSuppression.suppressed?("full@example.com")
  end

  test "a message that isn't Amazon's, or from another topic, is refused" do
    post ses_webhook_path, params: { "Type" => "Notification", "Message" => "{}" }.to_json, headers: { "Content-Type" => "text/plain" }
    assert_response :forbidden

    Rails.configuration.x.ses = { sns_topic_arn: "arn:aws:sns:eu-west-1:123:another-topic" }
    post_event("eventType" => "Complaint", "complaint" => { "complainedRecipients" => [ { "emailAddress" => "x@example.com" } ] }, "mail" => {})
    assert_response :forbidden
    assert_not EmailSuppression.suppressed?("x@example.com")
  ensure
    Rails.configuration.x.ses = nil
  end

  test "a shop sees that a customer's address bounces" do
    Account.without_isolation { customers(:acme_contractor).update_columns(email: "contractor@example.com") }
    EmailSuppression.record_bounce("contractor@example.com", bounce_type: "Permanent")

    sign_in_as users(:amina)
    get customer_path(customers(:acme_contractor))
    assert_select "[data-tour=customer-details]", /Emails to this address bounce/
  end
end
