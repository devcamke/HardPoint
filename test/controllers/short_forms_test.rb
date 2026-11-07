require "test_helper"

# The everyday fields up front, the rest folded under "More options" with a line saying what they're set to.
class ShortFormsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:amina) }

  test "new customer: name, phone and credit limit up front" do
    get new_customer_path
    assert_select "form > .grid input[name='customer[phone]']"
    assert_select "form > .grid input[name='customer[credit_limit]']"
    assert_select "details summary", /retail prices · pays within 30 days · no tax PIN/
    assert_select "details input[name='customer[tax_pin]']"
    assert_select "details select[name='customer[price_list_id]']"
  end

  test "new supplier: name, phone and order email up front" do
    get new_supplier_path
    assert_select "form > .grid input[name='supplier[email]']"
    assert_select "details summary", /invoices in KES · pay within 30 days/
    assert_select "details input[name='supplier[contact_name]']"
  end

  test "new purchase order: supplier and products up front, delivery details folded" do
    get new_purchase_order_path(branch_id: branches(:acme_main).id)
    assert_select "form > .field select[name='purchase_order[supplier_id]']"
    assert_select "details summary", /deliver to Main branch · no expected date · no note/
    assert_select "details select[name='purchase_order[branch_id]']"
    assert_select "details input[name='purchase_order[note]']"
  end

  test "new quote: customer and products up front, branch and dates folded" do
    get new_customer_order_path(branch_id: branches(:acme_main).id)
    assert_select "form > .grid select[name='customer_order[customer_id]']"
    assert_select "details summary", /at Main branch · valid until 14 days from today · no date needed · no note/
    assert_select "details input[name='customer_order[valid_until]']"
  end

  test "a mistake in a folded field opens More options" do
    post customers_path, params: { customer: { name: "Baraka Builders", email: "not-an-email" } }
    assert_response :unprocessable_entity
    assert_select "details[open]"
  end
end
