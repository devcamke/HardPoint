require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  test "the owner's dashboard shows the checklist until it's hidden" do
    get root_path
    assert_select "#onboarding_card", /Set up your shop/

    get onboarding_path
    assert_select "#step_products span", "✓"
    assert_select "#step_taxes span", "2"

    post onboarding_tax_confirmation_path
    assert Account.without_isolation { @account.reload.taxes_confirmed_at }

    post onboarding_completion_path
    get root_path
    assert_select "#onboarding_card", count: 0
  end

  test "a test receipt, and saying it printed" do
    get onboarding_test_receipt_path
    assert_select ".receipt", /TEST RECEIPT, NOT A SALE/

    post onboarding_test_receipt_path
    assert_redirected_to onboarding_path
    assert Account.without_isolation { @account.reload.test_receipt_printed_at }
  end

  test "only owners set up the shop" do
    sign_out
    sign_in_as users(:carl), account: @account
    get onboarding_path
    assert_response :forbidden

    get root_path
    assert_select "#onboarding_card", count: 0
  end
end
