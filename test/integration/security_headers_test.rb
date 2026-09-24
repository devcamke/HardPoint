require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "pages carry a content security policy, and the importmap script its nonce" do
    sign_in_as users(:amina), account: accounts(:acme)
    get root_path

    policy = response.headers["Content-Security-Policy"]
    assert_match "script-src 'self' 'nonce-", policy
    assert_match "object-src 'none'", policy
    assert_match "frame-ancestors 'none'", policy
    assert_match "form-action 'self' http://*.localhost https://checkout.paystack.com", policy

    nonce = policy[/'nonce-([^']+)'/, 1]
    assert_select "script[type=importmap][nonce=?]", nonce
    assert_select "[onclick]", count: 0
    assert_match "camera 'self'", response.headers["Permissions-Policy"] || response.headers["Feature-Policy"].to_s
  end

  test "receipts print without inline handlers" do
    use_apex_domain
    get "/"
    assert_select "[onclick], [onload]", count: 0
  end

  test "secrets, PINs and phone numbers stay out of the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("password" => "x", "pin" => "1234", "code" => "123456", "phone" => "0722", "kra_pin" => "P0",
      "MSISDN" => "2547", "product_code" => "CEM-50")

    assert_equal %w[ password pin code phone kra_pin MSISDN ], filtered.select { _2 == "[FILTERED]" }.keys
    assert_equal "CEM-50", filtered["product_code"]
  end
end
