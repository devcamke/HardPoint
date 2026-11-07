require "test_helper"

class Webhooks::AirtelControllerTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        @merchant = accounts(:acme).airtel_merchants.create!(name: "Airtel Money", environment: "simulator")
        @sale = shifts(:acme_front_open).current_sale
        @sale.add(products(:acme_nails), quantity: 4)
        @prompt = @merchant.requests.create!(account: accounts(:acme), sale: @sale, phone: "254733000111", amount_cents: @sale.balance_due_cents)
      end
    end
    use_apex_domain
  end

  def callback(status_code: "TS", id: @prompt.transaction_id)
    { transaction: { id: id, status_code: status_code, airtel_money_id: "MP261107.1234.A12345", message: "Paid" } }.to_json
  end

  test "a paid callback pays the sale once, however often it arrives" do
    2.times do
      post airtel_webhook_path(@merchant.callback_token), params: callback, headers: { "Content-Type" => "application/json" }
      assert_response :success
    end
    Account.without_isolation do
      assert @sale.reload.completed?
      assert_equal 1, @sale.payments.where(tender: "airtel_money").count
      assert_equal "MP261107.1234.A12345", @sale.payments.sole.reference
    end
  end

  test "rubbish and unknown transactions are accepted and ignored" do
    post airtel_webhook_path(@merchant.callback_token), params: "not json", headers: { "Content-Type" => "application/json" }
    assert_response :success
    post airtel_webhook_path(@merchant.callback_token), params: callback(id: "HPNOTOURS"), headers: { "Content-Type" => "application/json" }
    assert_response :success
    assert Account.without_isolation { @prompt.reload.pending? }
  end

  test "an unknown token is not found" do
    post airtel_webhook_path("x" * 36), params: callback, headers: { "Content-Type" => "application/json" }
    assert_response :not_found
  end
end
