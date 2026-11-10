require "test_helper"

class Webhooks::WhatsappControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV["WHATSAPP_APP_SECRET"], ENV["WHATSAPP_VERIFY_TOKEN"] = "app-secret", "verify-me"
    @message = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).whatsapp_messages.create!(template: "hardpoint_document", to_phone: "254722000111", status: "sent", provider_message_id: "wamid.XYZ")
      end
    end
  end

  teardown do
    ENV.delete("WHATSAPP_APP_SECRET")
    ENV.delete("WHATSAPP_VERIFY_TOKEN")
  end

  def update(status, signature: nil)
    body = { entry: [ { changes: [ { value: { statuses: [ { id: "wamid.XYZ", status: status, timestamp: Time.current.to_i.to_s } ] } } ] } ] }.to_json
    signature ||= "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "app-secret", body)}"
    post whatsapp_webhook_path, params: body, headers: { "Content-Type" => "application/json", "X-Hub-Signature-256" => signature }
  end

  test "Meta checks the address with our verify token" do
    get whatsapp_webhook_path, params: { "hub.mode" => "subscribe", "hub.verify_token" => "verify-me", "hub.challenge" => "12345" }
    assert_equal "12345", response.body
    get whatsapp_webhook_path, params: { "hub.mode" => "subscribe", "hub.verify_token" => "wrong", "hub.challenge" => "12345" }
    assert_response :forbidden
  end

  test "a signed update moves the message on; an unsigned one is refused" do
    update "read"
    assert_response :ok
    assert_equal "read", Account.without_isolation { @message.reload.status }

    update "delivered", signature: "sha256=forged"
    assert_response :unauthorized
  end
end
