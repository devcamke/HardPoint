require "test_helper"

class SupplierReturnsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
  end

  def acme(&) = Account.without_isolation(&)

  test "return goods by scanning, email the debit note, note the credit note" do
    get new_supplier_return_path(supplier_id: suppliers(:acme_cement_distributor).id)
    assert_select "input[name*=product_code]"

    assert_enqueued_emails 1 do
      post supplier_returns_path, params: { email: "1", supplier_return: { supplier_id: suppliers(:acme_cement_distributor).id, branch_id: branches(:acme_main).id,
        reason: "damaged", note: "Split bags", lines_attributes: { "0" => { product_code: "CEM-50", quantity: "2" } } } }
    end
    supplier_return = acme { @account.supplier_returns.last }
    assert_redirected_to supplier_return_path(supplier_return)
    follow_redirect!
    assert_select "h1", /MAIN-SR00001/

    get supplier_return_path(supplier_return, format: :pdf)
    assert_equal "application/pdf", response.media_type

    post supplier_return_credit_note_path(supplier_return), params: { credit_note_number: "CN-1", credited_on: Date.current }
    assert acme { supplier_return.reload.credited? }

    get supplier_returns_path(filter: "all")
    assert_select "##{dom_id(supplier_return)}", /CN-1/
    get supplier_path(suppliers(:acme_cement_distributor))
    assert_select "a", text: "MAIN-SR00001"
  end

  test "mistakes come back to the form" do
    post supplier_returns_path, params: { supplier_return: { supplier_id: suppliers(:acme_cement_distributor).id, branch_id: branches(:acme_main).id,
      reason: "damaged", lines_attributes: { "0" => { product_code: "NOPE-1", quantity: "2" } } } }
    assert_response :unprocessable_entity
    assert_match "NOPE-1", response.body
  end

  test "cashiers can't return goods to suppliers" do
    sign_in_as users(:carl), account: @account
    get new_supplier_return_path
    assert_response :forbidden
  end
end
