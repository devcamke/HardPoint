require "test_helper"

class HireTermsControllerTest < ActionDispatch::IntegrationTest
  def acme = Account.without_isolation { accounts(:acme).reload }

  test "an owner writes the shop's terms, sees them as they'll print, and can go back to the standard ones" do
    sign_in_as users(:amina)

    get edit_hire_terms_path
    assert_select "textarea[name='account[hire_terms]']", /The tools remain the property of the shop/
    assert_select "ol li", Account::HireTerms::STANDARD.size

    patch hire_terms_path, params: { account: { hire_terms: "Tools stay ours.\nPay for damage." } }
    assert_redirected_to edit_hire_terms_path
    assert_equal [ "Tools stay ours.", "Pay for damage." ], acme.hire_terms_list
    follow_redirect!
    assert_select "ol li", 2
    assert_select "button[name=reset]"

    patch hire_terms_path, params: { reset: "1", account: { hire_terms: "ignored" } }
    assert_not acme.own_hire_terms?
  end

  test "terms that don't fit are refused with a reason" do
    sign_in_as users(:amina)
    patch hire_terms_path, params: { account: { hire_terms: "x" * 601 } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation", /too long/
    assert_not acme.own_hire_terms?
  end

  test "only owners and managers change them, and the change is in the activity log" do
    sign_in_as users(:carl)
    get edit_hire_terms_path
    assert_response :forbidden

    sign_in_as users(:amina)
    patch hire_terms_path, params: { account: { hire_terms: "Tools stay ours." } }
    assert Account.without_isolation { Event.where(account: accounts(:acme)).order(:id).last.particulars.to_s.include?("hire_terms") }
  end

  test "reached from Tools for hire, Settings and search" do
    sign_in_as users(:amina)

    get hire_items_path
    assert_select "a[href='#{edit_hire_terms_path}']", "Hire terms"
    get settings_path
    assert_select "a[href='#{edit_hire_terms_path}']"
    get search_path(q: "hire terms"), headers: { "Turbo-Frame" => "search_results" }
    assert_select "a[href=?]", edit_hire_terms_path(from: "search:pages")
  end
end
