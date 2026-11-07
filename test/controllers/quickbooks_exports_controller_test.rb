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
end
