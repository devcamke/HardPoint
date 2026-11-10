require "test_helper"

class OnboardingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  test "the owner's dashboard shows the checklist until setup is finished" do
    get root_path
    assert_select "#onboarding_card", /Set up your shop/

    get onboarding_path
    assert_select "#step_products span", "✓"
    assert_select "#step_taxes span", "2"

    post onboarding_tax_confirmation_path
    assert Account.without_isolation { @account.reload.taxes_confirmed_at }

    post onboarding_completion_path
    assert_redirected_to onboarding_path
    assert_equal "Not finished yet: Print a test receipt.", flash[:alert]
    assert_nil Account.without_isolation { @account.reload.onboarding_completed_at }

    post onboarding_test_receipt_path
    post onboarding_completion_path
    assert_redirected_to root_path
    get root_path
    assert_select "#onboarding_card", count: 0
  end

  test "branches and tills are done once there's an address and a till; staff are optional" do
    signup = Signup.new(shop_name: "Mjengo Hardware", subdomain: "mjengo", owner_name: "Wanjiru",
      email_address: "wanjiru@mjengo.test", password: "a long password", terms_accepted: true)
    assert signup.save
    account = signup.account

    Account.without_isolation do
      Current.set(account: account) do
        branches = -> { Onboarding.new(account).steps.find { _1.key == :branches } }
        account.branches.sole.update!(address: "Kenyatta Avenue")
        assert_not branches.call.done?, "an address alone isn't enough"

        account.registers.create!(name: "Counter", branch: account.branches.sole)
        assert branches.call.done?
        assert Onboarding.new(account).steps.find { _1.key == :staff }.optional?, "a sole trader can be ready"
      end
    end
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
