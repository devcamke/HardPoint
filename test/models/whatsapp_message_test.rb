require "test_helper"

class WhatsappMessageTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # Stands in for Meta: records what's posted, answers as told.
  class FakeTransport
    attr_reader :requests
    def initialize(response) = (@response, @requests = response, [])

    def request(method, url, headers: {}, json: nil, form: nil)
      @requests << { method:, url:, headers:, json: }
      @response
    end
  end

  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:amina))
    @customer = customers(:acme_contractor)
    @customer.update!(phone: "0722 000 111")
    stock_up products(:acme_nails), 10
    @sale = shifts(:acme_front_open).current_sale
    @sale.change_customer(@customer)
    @sale.add(products(:acme_nails), quantity: 4)
    @sale.pay(tender: "cash", tendered_cents: 1000_00)
  end

  # Runs the sending job, which leaves the shop it ran for when it's done, and reads the message back in this shop.
  def sent(&)
    message = perform_enqueued_jobs(&)
    Current.account = accounts(:acme)
    message.reload
  end

  def with_live_whatsapp(response)
    transport = FakeTransport.new(response)
    original = Whatsapp::Client.transport
    Whatsapp::Client.transport = transport
    ENV["WHATSAPP_PHONE_NUMBER_ID"], ENV["WHATSAPP_ACCESS_TOKEN"] = "1234567890", "token"
    yield transport
  ensure
    Whatsapp::Client.transport = original
    ENV.delete("WHATSAPP_PHONE_NUMBER_ID")
    ENV.delete("WHATSAPP_ACCESS_TOKEN")
  end

  test "numbers are written as WhatsApp wants them, and nonsense is refused" do
    assert_equal "254722000111", Whatsapp.recipient("0722 000 111")
    assert_equal "254722000111", Whatsapp.recipient("+254 722 000 111")
    assert_equal "254722000111", Whatsapp.recipient("722000111")
    assert_nil Whatsapp.recipient("12")

    message = Whatsapp::Message.deliver_document(@sale, phone: "12")
    assert_not message.persisted?
    assert_match "isn't a phone number", message.errors.full_messages.to_sentence
  end

  test "in test mode a receipt is recorded as simulated, with a share link to its PDF, and nothing is sent" do
    assert Whatsapp.simulated?
    message = sent { Whatsapp::Message.deliver_document(@sale, phone: @customer.phone, name: @customer.name) }
    assert_equal [ "simulated", "254722000111", "receipt" ], [ message.status, message.to_phone, message.document_share.kind ]
    assert_match %r{/share/#{message.document_share.token}\.pdf\z}, message.document_share.url(format: :pdf)
    assert_equal "Test mode", message.label
  end

  test "live, the template goes to Meta with the PDF attached and the shop's details filled in" do
    with_live_whatsapp(JsonHttp::Response.new(200, { "messages" => [ { "id" => "wamid.ABC" } ] })) do |meta|
      message = sent { Whatsapp::Message.deliver_document(@sale, phone: @customer.phone) }
      assert_equal [ "sent", "wamid.ABC" ], [ message.status, message.provider_message_id ]

      sent = meta.requests.sole
      assert_equal "https://graph.facebook.com/v21.0/1234567890/messages", sent[:url]
      assert_equal "Bearer token", sent[:headers]["Authorization"]
      template = sent[:json][:template]
      assert_equal "hardpoint_document", template[:name]
      assert_match(/\.pdf\z/, template[:components].first[:parameters].first[:document][:link])
      assert_equal [ "Acme Hardware", "your receipt", @sale.receipt_number, "KES 1,000.00" ], template[:components].last[:parameters].map { _1[:text] }
    end
  end

  test "a refusal from Meta is kept on the message" do
    with_live_whatsapp(JsonHttp::Response.new(400, { "error" => { "message" => "Template name does not exist in the translation" } })) do
      message = sent { Whatsapp::Message.deliver_document(@sale, phone: @customer.phone) }
      assert_equal [ "failed", "Template name does not exist in the translation" ], [ message.status, message.error ]
    end
  end

  test "a balance reminder carries the statement and what's owed" do
    @customer.update_columns(phone: "0722 000 111")
    message = sent { Whatsapp::Message.deliver_balance_reminder(@customer) }
    assert_equal [ "hardpoint_balance_reminder", "statement" ], [ message.template, message.document_share.kind ]
    assert_equal [ "Acme Hardware", @customer.name ], message.send(:parameters).first(2)
  end

  test "statuses only move forward" do
    message = sent { Whatsapp::Message.deliver_document(@sale, phone: @customer.phone) }
    message.update!(status: "sent")
    message.record_status("read", at: Time.current)
    message.record_status("delivered", at: Time.current)
    assert_equal "read", message.reload.status
    message.record_status("failed", at: Time.current, error: "Message undeliverable")
    assert_equal [ "failed", "Message undeliverable" ], [ message.reload.status, message.error ]
  end
end
