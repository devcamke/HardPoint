require "test_helper"

class AccountDataControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  def acme = Account.without_isolation { @account.reload }

  test "the owner exports everything and downloads the ZIP" do
    get account_data_path
    assert_select "#export", /Export everything/

    perform_enqueued_jobs(only: AccountExportJob) { post account_exports_path }
    assert_redirected_to account_data_path
    export = Account.without_isolation { @account.account_exports.last }
    assert Account.without_isolation { export.reload.ready? }

    get account_export_path(export)
    assert_response :success
    assert_equal "application/zip", response.media_type
    assert response.body.start_with?("PK")
  end

  test "exports work while the shop is read-only" do
    Account.without_isolation { @account.update!(subscription_status: "read_only") }
    assert_difference -> { Account.without_isolation { AccountExport.count } } do
      post account_exports_path
    end
  end

  test "only owners" do
    sign_out
    sign_in_as users(:carl), account: @account
    get account_data_path
    assert_response :forbidden
    post account_exports_path
    assert_response :forbidden
  end

  test "closing needs the shop's address typed and the password, and can be cancelled" do
    post account_closure_path, params: { confirmation: "nope", password: "password" }
    assert_not acme.closing?

    post account_closure_path, params: { confirmation: "acme", password: "password" }
    assert acme.closing?
    follow_redirect!
    assert_select "#closure", /will be deleted on/
    assert_select "#subscription_banner", /This shop is closing/

    delete account_closure_path
    assert_not acme.closing?
  end

  test "while closing, staff can't sign in and nothing can be changed" do
    post account_closure_path, params: { confirmation: "acme", password: "password" }

    post branches_path, params: { branch: { name: "Westlands" } }
    assert_match "closing", flash[:alert]

    sign_out
    post session_path, params: { email_address: users(:carl).email_address, password: "password" }
    assert_redirected_to new_session_path
    assert_match "only its owners can sign in", flash[:alert]
  end
end
