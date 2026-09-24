require "test_helper"

class SupportRequestsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    sign_in_as users(:carl), account: @account
  end

  test "anyone in the shop can ask for help, with the page they were on" do
    get new_support_request_path, headers: { "Referer" => "http://acme.localhost/pos" }
    assert_select "input[name='support_request[page]'][value='/pos']"
    assert_select "a[href^='https://wa.me/']"

    assert_enqueued_emails 1 do
      post support_requests_path, params: { support_request: { subject: "Drawer won't open", body: "Since this morning.", page: "/pos" } }
    end
    assert_redirected_to new_support_request_path

    request = Account.without_isolation { SupportRequest.last }
    assert_equal [ users(:carl), "/pos", "open" ], [ request.user, request.page, request.status ]
  end

  test "the email reaches support, and replies go to whoever asked" do
    request = Account.without_isolation do
      Current.set(account: @account) { @account.support_requests.create!(user: users(:carl), subject: "Help", body: "Please") }
    end
    email = SupportMailer.with(support_request: request).received
    assert_equal [ "support@hardpoint.app" ], email.to
    assert_equal [ users(:carl).email_address ], email.reply_to
    assert_match "Acme Hardware", email.subject
  end

  test "a read-only shop can still ask for help" do
    Account.without_isolation { @account.update!(subscription_status: "read_only") }
    assert_difference -> { Account.without_isolation { SupportRequest.count } } do
      post support_requests_path, params: { support_request: { subject: "Invoice", body: "Paid already?" } }
    end
  end
end
