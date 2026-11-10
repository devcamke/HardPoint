require "test_helper"

class RebalancingTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)

  test "the reorder list offers the move first, and the transfer it prepares arrives filled in" do
    yard, main = acme { branches(:acme_yard) }, acme { branches(:acme_main) }
    cement = acme { products(:acme_cement) }
    sign_in_as users(:amina)

    get reorder_list_path, params: { branch_id: yard.id }
    assert_select "h2", "Move from another branch first"
    assert_select "a[href*='#{new_stock_transfer_path}']", "Prepare the transfer"

    get new_stock_transfer_path, params: { from_branch_id: main.id, to_branch_id: yard.id, lines: [ { product_id: cement.id, quantity: "10" } ] }
    assert_select "select[name='stock_transfer[from_branch_id]'] option[selected][value='#{main.id}']"
    assert_select "select[name='stock_transfer[to_branch_id]'] option[selected][value='#{yard.id}']"
    assert_select "input[name='stock_transfer[lines_attributes][0][product_code]'][value='#{cement.sku}']"
    assert_select "input[name='stock_transfer[lines_attributes][0][quantity]'][value='10']"
  end

  test "the morning email suggests the move" do
    acme do
      Current.set(account: accounts(:acme)) do
        html = ReportsMailer.with(account: accounts(:acme), date: Time.use_zone(accounts(:acme).time_zone) { Time.zone.yesterday }).daily_summary.html_part.body.to_s
        assert_match "Move it instead of ordering", html
        assert_match "Bamburi cement 50kg", html
      end
    end
  end
end
