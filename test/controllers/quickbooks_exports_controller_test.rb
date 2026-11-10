require "test_helper"

class QuickbooksExportsControllerTest < ActionDispatch::IntegrationTest
  test "owners and accountants download a month and set the account names" do
    sign_in_as users(:amina)
    get reports_path
    assert_select "a[href='#{quickbooks_export_path}']", /QuickBooks export/

    get quickbooks_export_path
    assert_select "input[name='accounts[cash]'][value='Cash on hand']"

    patch quickbooks_export_path, params: { accounts: { cash: "Till cash", sales: "Sales of Product Income" } }
    assert_equal({ "cash" => "Till cash" }, Account.without_isolation { accounts(:acme).reload.quickbooks_accounts })

    get quickbooks_export_path(format: :zip, month: Date.current.strftime("%Y-%m"))
    assert_equal "application/zip", response.media_type
    assert_match "acme-quickbooks-#{Date.current.strftime("%Y-%m")}.zip", response.headers["Content-Disposition"]
  end

  test "cashiers can't" do
    sign_in_as users(:carl)
    get quickbooks_export_path
    assert_response :forbidden
  end

  test "a manager bound to a branch can't download the whole shop's books" do
    Account.without_isolation { memberships(:sara_acme).update!(role: "manager", branch: branches(:acme_yard)) }
    sign_in_as users(:sara)

    get reports_path
    assert_select "a[href='#{quickbooks_export_path}']", count: 0
    get quickbooks_export_path(format: :zip, month: Date.current.strftime("%Y-%m"))
    assert_redirected_to reports_path
    assert_match "only staff who see every branch", flash[:alert]
    patch quickbooks_export_path, params: { accounts: { cash: "Till cash" } }
    assert_redirected_to reports_path
    assert_equal({}, Account.without_isolation { accounts(:acme).reload.quickbooks_accounts })
  end
end
