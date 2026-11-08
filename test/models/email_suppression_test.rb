require "test_helper"

class EmailSuppressionTest < ActiveSupport::TestCase
  test "permanent bounces and complaints suppress an address; transient bounces don't" do
    assert_nil EmailSuppression.record_bounce("Full@Example.com", bounce_type: "Transient", bounce_subtype: "MailboxFull")
    assert_not EmailSuppression.suppressed?("full@example.com")

    EmailSuppression.record_bounce("Gone@Example.com", bounce_type: "Permanent", bounce_subtype: "NoEmail", detail: "550 5.1.1 user unknown")
    assert EmailSuppression.suppressed?("GONE@example.com")
    assert_equal "NoEmail: 550 5.1.1 user unknown", EmailSuppression.for("gone@example.com").detail

    EmailSuppression.record_bounce("gone@example.com", bounce_type: "Permanent", bounce_subtype: "General")
    assert_equal 2, EmailSuppression.for("gone@example.com").count, "the same address reported again is one row"

    EmailSuppression.record_complaint("angry@example.com", detail: "abuse")
    assert_equal "This address reported our email as spam", EmailSuppression.for("angry@example.com").description
  end

  test "suppressed addresses are dropped from emails, and an email with nobody left isn't sent" do
    EmailSuppression.record_complaint("angry@example.com")

    mail = Mail.new(to: [ "angry@example.com", "fine@example.com" ], cc: "angry@example.com", subject: "Hello")
    EmailSuppression::Interceptor.delivering_email(mail)
    assert_equal [ "fine@example.com" ], mail.to
    assert_nil mail.cc
    assert mail.perform_deliveries

    alone = Mail.new(to: "angry@example.com", subject: "Hello")
    EmailSuppression::Interceptor.delivering_email(alone)
    assert_not alone.perform_deliveries

    # Through Action Mailer itself: the interceptor is registered.
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        sale = shifts(:acme_front_open).current_sale.tap { _1.add(products(:acme_nails)); _1.pay(tender: "cash") }
        assert_no_difference -> { ActionMailer::Base.deliveries.size } do
          SalesMailer.with(sale: sale, email: "angry@example.com").receipt.deliver_now
        end
        assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
          SalesMailer.with(sale: sale, email: "fine@example.com").receipt.deliver_now
        end
      end
    end
  end

  test "lifting a suppression also removes it from SES's list when the API is in use" do
    Rails.configuration.x.ses = { region: "eu-west-1", access_key_id: "AKIATEST", secret_access_key: "secret" }
    Ses.reset_clients!
    client = Aws::SESV2::Client.new(stub_responses: true)
    Ses.client = client

    suppression = EmailSuppression.record_complaint("angry@example.com")
    suppression.lift!
    assert_not EmailSuppression.suppressed?("angry@example.com")
    assert_equal [ :delete_suppressed_destination ], client.api_requests.map { _1[:operation_name] }
  ensure
    Rails.configuration.x.ses = nil
    Ses.reset_clients!
  end
end
