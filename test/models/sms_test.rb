require "test_helper"

class SmsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    Current.account = accounts(:acme)
    Current.session = @session = accounts(:acme).sessions.create!(user: users(:carl))
    accounts(:acme).update!(sms_enabled: true)
  end

  def delivering(&)
    perform_enqueued_jobs(only: Sms::DeliveryJob, &)
  ensure
    Current.account = accounts(:acme)
    Current.session = @session
  end

  test "texts go through Africa's Talking with the platform's credentials, and what happened is kept" do
    fake = fake_transport(Sms::AfricasTalking, "/version1/messaging" => { SMSMessageData: { Recipients: [
      { statusCode: 101, number: "+254722000111", status: "Success", cost: "KES 0.8000", messageId: "ATXid_1" } ] } })
    Rails.configuration.x.sms_outbox = false

    text = delivering { Sms::Message.compose(to: "0722 000 111", body: "Hello", purpose: "receipt") }

    assert text.reload.sent?
    assert_equal [ "ATXid_1", "KES 0.8000" ], [ text.provider_message_id, text.cost ]
    assert_equal({ to: "+254722000111", message: "Hello" }, fake.requests.sole.form.slice(:to, :message))
  ensure
    Rails.configuration.x.sms_outbox = true
  end

  test "a refused text is marked failed with the reason" do
    fake_transport(Sms::AfricasTalking, "/version1/messaging" => { SMSMessageData: { Message: "InvalidSenderId", Recipients: [] } })
    Rails.configuration.x.sms_outbox = false

    text = delivering { Sms::Message.compose(to: "0722000111", body: "Hello", purpose: "receipt") }
    assert text.reload.failed?
    assert_equal "InvalidSenderId", text.error
  ensure
    Rails.configuration.x.sms_outbox = true
  end

  test "receipt, order ready and balance reminder texts" do
    sale = shifts(:acme_front_open).current_sale
    sale.add(products(:acme_nails), quantity: 4)
    sale.change_customer(customers(:acme_contractor))
    sale.pay(tender: "on_account")
    accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator")

    Sms::Message.receipt(sale, to: "0722000111")
    Sms::Message.balance_reminder(customers(:acme_contractor))
    delivering { perform_enqueued_jobs }

    receipt, reminder = Sms::Outbox.deliveries.map { _1[:message] }
    assert_match "receipt #{sale.receipt_number}", receipt
    assert_match "Total KES 1,000.00 paid by on account", receipt
    assert_equal "Acme Hardware: your account balance is KES 1,000.00. Pay to Paybill 174379, account 0722000111. Thank you.", reminder
    assert Sms::Outbox.deliveries.all? { _1[:message].length <= 160 }
  end

  test "SMS has to be turned on, numbers must be mobiles, and each shop has a daily limit" do
    assert_match "must be a Kenyan mobile", Sms::Message.compose(to: "020 000 000", body: "Hi", purpose: "receipt").errors.full_messages.to_sentence

    accounts(:acme).update!(sms_enabled: false)
    assert_match "SMS is turned off", Sms::Message.compose(to: "0722000111", body: "Hi", purpose: "receipt").errors.full_messages.to_sentence

    accounts(:acme).update!(sms_enabled: true)
    stub_const(Sms::Message, :DAILY_LIMIT, 1) do
      assert Sms::Message.compose(to: "0722000111", body: "Hi", purpose: "receipt").persisted?
      assert_match "sent its 1 texts", Sms::Message.compose(to: "0722000111", body: "Hi", purpose: "receipt").errors.full_messages.to_sentence
    end
  end
end
