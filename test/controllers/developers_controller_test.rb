require "test_helper"

class DevelopersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  test "an owner makes a key, sees it once, and revokes it" do
    post api_keys_path, params: { api_key: { name: "Web shop", scope: "write" } }
    assert_response :created
    token = css_select("#token").first["value"]
    assert token.start_with?("hp_")

    key = Account.without_isolation { ApiKey.find_by!(token_digest: ApiKey.digest(token)) }
    assert key.writable?

    get developers_path
    assert_select "#api_keys", /Web shop/
    assert_select "#api_keys", text: /#{token}/, count: 0

    delete api_key_path(key)
    assert Account.without_isolation { key.reload.revoked? }
    assert_equal "revoked", Account.without_isolation { key.events.last.action }
  end

  test "an owner adds a webhook endpoint, tests it and sees the delivery" do
    fake_transport(WebhookDelivery, "/hooks" => {})
    post webhook_endpoints_path, params: { webhook_endpoint: { url: "https://shop.example.com/hooks", event_types: [ "", "sale.completed", "product.updated" ] } }
    endpoint = Account.without_isolation { @account.webhook_endpoints.last }
    assert_redirected_to webhook_endpoint_path(endpoint)
    assert_equal %w[ sale.completed product.updated ], endpoint.event_types

    perform_enqueued_jobs { post webhook_endpoint_test_path(endpoint) }
    get webhook_endpoint_path(endpoint)
    assert_select "#deliveries", /ping/
    assert_select "#deliveries", /Delivered/
  end

  test "cashiers can't manage developer settings" do
    sign_out
    sign_in_as users(:carl), account: @account
    get developers_path
    assert_response :forbidden
  end

  test "the Starter plan is told the API needs a bigger plan" do
    Account.without_isolation { @account.update!(plan: "starter") }
    get developers_path
    assert_match "Business and Enterprise", response.body
    post api_keys_path, params: { api_key: { name: "Nope", scope: "read" } }
    assert_response :unprocessable_entity
  end

  test "the public API documentation" do
    use_apex_domain
    get developer_docs_path
    assert_select "h1", "API and webhooks"
    assert_select "code", "sale.completed"
  end
end
