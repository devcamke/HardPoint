require "test_helper"

class SesTest < ActiveSupport::TestCase
  setup do
    Rails.configuration.x.ses = { region: "eu-west-1", access_key_id: "AKIATEST", secret_access_key: "secret", configuration_set: "hardpoint-test", sns_topic_arn: "arn:aws:sns:eu-west-1:123:hardpoint-ses-events" }
    Ses.reset_clients!
    @client = Aws::SESV2::Client.new(stub_responses: true)
    Ses.client = @client
  end

  teardown do
    Rails.configuration.x.ses = nil
    Ses.reset_clients!
  end

  test "settings come from the credentials, and the API is used when there's an access key" do
    assert Ses.api?
    assert Ses.configured?
    assert_equal [ "eu-west-1", "hardpoint-test", "hardpoint.app" ], [ Ses.region, Ses.configuration_set, Ses.sending_domain ]

    Rails.configuration.x.ses = { smtp_username: "AKIA", smtp_password: "x" }
    assert_not Ses.api?
    assert Ses.smtp?
  end

  test "a mail goes through SendEmail under the configuration set, tagged with its mailer" do
    @client.stub_responses(:send_email, { message_id: "0102abc" })
    mail = Mail.new(from: "HardPoint <no-reply@hardpoint.app>", to: "amina@acme.test", subject: "Hello", body: "Hi")
    mail.header["X-HardPoint-Mailer"] = "Billing_invoice"

    Ses::Delivery.new.deliver!(mail)

    request = @client.api_requests.sole
    assert_equal :send_email, request[:operation_name]
    params = request[:params]
    assert_equal [ "no-reply@hardpoint.app", [ "amina@acme.test" ], "hardpoint-test" ], [ params[:from_email_address], params[:destination][:to_addresses], params[:configuration_set_name] ]
    assert_equal [ { name: "mailer", value: "Billing_invoice" } ], params[:email_tags]
    assert_match "Subject: Hello", params[:content][:raw][:data]
    assert_equal "0102abc@eu-west-1.amazonses.com", mail.message_id
  end

  test "the account's standing is read from GetAccount" do
    @client.stub_responses(:get_account, { sending_enabled: true, production_access_enabled: false, enforcement_status: "HEALTHY",
      send_quota: { max_24_hour_send: 50_000.0, sent_last_24_hours: 41_000.0, max_send_rate: 14.0 } })

    account = Ses.account
    assert account.healthy?
    assert_not account.production
    assert_equal 82, account.quota_used_percent
  end

  test "the platform's email check reads SES's standing and recent complaints" do
    @client.stub_responses(:get_account, { sending_enabled: true, production_access_enabled: true, enforcement_status: "HEALTHY",
      send_quota: { max_24_hour_send: 50_000.0, sent_last_24_hours: 100.0, max_send_rate: 14.0 } })
    check = PlatformHealth.check.checks.find { _1.name == :email }
    assert check.ok?
    assert_equal "SES sending, 0% of today's quota used", check.detail

    EmailSuppression.record_complaint("angry@example.com")
    check = PlatformHealth.check.checks.find { _1.name == :email }
    assert_equal [ :warning, "1 spam complaint in the last day" ], [ check.status, check.detail ]

    @client.stub_responses(:get_account, { sending_enabled: false, enforcement_status: "SHUTDOWN", send_quota: { max_24_hour_send: 50_000.0, sent_last_24_hours: 0.0 } })
    check = PlatformHealth.check.checks.find { _1.name == :email }
    assert check.failing?
    assert_match "paused", check.detail
  end

  test "every mailer tags its emails with the mailer and action" do
    mail = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        sale = shifts(:acme_front_open).current_sale.tap { _1.add(products(:acme_nails)); _1.pay(tender: "cash") }
        SalesMailer.with(sale: sale, email: "x@example.com").receipt
      end
    end
    assert_equal "Sales_receipt", mail.header["X-HardPoint-Mailer"].value
  end

  test "ses:setup verifies the domain, makes the configuration set and wires the SNS topic to the webhook" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("ses:setup")
    sns = Aws::SNS::Client.new(stub_responses: true)
    sns.stub_responses(:create_topic, { topic_arn: "arn:aws:sns:eu-west-1:123:hardpoint-ses-events" })
    Ses.sns_client = sns
    @client.stub_responses(:get_email_identity, { verified_for_sending_status: true, dkim_attributes: { status: "SUCCESS", tokens: %w[ tok1 tok2 tok3 ] },
      mail_from_attributes: { mail_from_domain: "mail.hardpoint.app", mail_from_domain_status: "SUCCESS", behavior_on_mx_failure: "USE_DEFAULT_VALUE" } })
    @client.stub_responses(:get_account, { sending_enabled: true, production_access_enabled: true, enforcement_status: "HEALTHY", send_quota: { max_24_hour_send: 50_000.0, sent_last_24_hours: 0.0, max_send_rate: 14.0 } })

    output, = capture_io { Rake::Task["ses:setup"].execute }

    operations = @client.api_requests.map { _1[:operation_name] }
    assert_includes operations, :create_email_identity
    assert_includes operations, :put_email_identity_mail_from_attributes
    assert_includes operations, :put_account_suppression_attributes
    assert_includes operations, :create_configuration_set
    assert_includes operations, :create_configuration_set_event_destination
    destination = @client.api_requests.find { _1[:operation_name] == :create_configuration_set_event_destination }[:params][:event_destination]
    assert_equal [ %w[ BOUNCE COMPLAINT REJECT ], "arn:aws:sns:eu-west-1:123:hardpoint-ses-events" ], [ destination[:matching_event_types], destination[:sns_destination][:topic_arn] ]
    subscription = sns.api_requests.find { _1[:operation_name] == :subscribe }[:params]
    assert_equal [ "https", "http://localhost/webhooks/ses" ], [ subscription[:protocol], subscription[:endpoint] ]
    assert_match "CNAME  tok1._domainkey.hardpoint.app  →  tok1.dkim.amazonses.com", output
    assert_match "MX     mail.hardpoint.app  →  10 feedback-smtp.eu-west-1.amazonses.com", output
  end
end
