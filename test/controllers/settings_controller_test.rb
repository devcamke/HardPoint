require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "an owner sees every setting as a card, grouped, each saying how it's set now" do
    sign_in_as users(:amina)
    get settings_path
    assert_response :success

    %w[ shop people selling payments-and-tax catalogue ].each { assert_select "section[data-tour='settings-#{_1}']" }
    assert_select "a[href='#{edit_appearance_path}']", /Appearance.*Petrol teal/m
    assert_select "a[href='#{edit_preferences_path}']", /Quotes valid 14 days/
    assert_select "a[href='#{features_path}']", /of #{Account::Features::KEYS.size} switched on/
    assert_select "a[href='#{edit_account_path(anchor: "alerts")}']", /Short over KES 2,000.00/
    assert_select "input[data-settings-filter-target=query]"
    assert_select "[data-settings-filter-target=card][data-search*='mpesa']"
  end

  test "a cashier sees only what their role uses" do
    sign_in_as users(:carl)
    get settings_path
    assert_response :success
    assert_select "a[href='#{branches_path}']"
    assert_select "a[href='#{edit_appearance_path}']", count: 0
    assert_select "a[href='#{memberships_path}']", count: 0
    assert_select "section[data-tour='settings-people']", count: 0
  end

  test "settings for switched-off features are left out" do
    Account.without_isolation { accounts(:acme).update!(features: Account::Features::KEYS - %w[ fundis online_store developers currencies ]) }
    sign_in_as users(:amina)
    get settings_path
    [ edit_fundi_rates_path, edit_storefront_path, developers_path, currencies_path ].each { assert_select "a[href='#{_1}']", count: 0 }
  end
end
