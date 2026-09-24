require "test_helper"

class StockTransfersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "send and receive a transfer" do
    post stock_transfers_path, params: { stock_transfer: { from_branch_id: branches(:acme_main).id, to_branch_id: branches(:acme_yard).id,
      lines_attributes: { "0" => { product_code: "CEM-50", quantity: "5" }, "1" => { product_code: "", quantity: "" } } } }

    transfer = Account.without_isolation { StockTransfer.last }
    assert_redirected_to stock_transfer_path(transfer)

    post stock_transfer_receipt_path(transfer)
    assert Account.without_isolation { transfer.reload.received? }
    assert_equal 15, Account.without_isolation { products(:acme_cement).stock_at(branches(:acme_yard)) }
  end

  test "problems keep the form" do
    post stock_transfers_path, params: { stock_transfer: { from_branch_id: branches(:acme_yard).id, to_branch_id: branches(:acme_main).id,
      lines_attributes: { "0" => { product_code: "CEM-50", quantity: "99" } } } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation", /Only 10/
  end

  test "can't send to another shop's branch" do
    post stock_transfers_path, params: { stock_transfer: { from_branch_id: branches(:acme_main).id, to_branch_id: branches(:bolt_main).id,
      lines_attributes: { "0" => { product_code: "CEM-50", quantity: "1" } } } }
    assert_response :not_found
  end
end
