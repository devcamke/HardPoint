require "test_helper"

class TransportChargesTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  def acme(&) = Account.without_isolation(&)

  def completed_sale(customer: nil)
    acme do
      Current.set(account: @account, user: users(:carl)) do
        shifts(:acme_front_open).current_sale.tap do |sale|
          sale.change_customer(customer) if customer
          sale.add(products(:acme_nails))
          sale.pay(tender: "cash")
        end
      end
    end
  end

  test "transport added at the till is its own line at what the trip costs, and the delivery note shows it" do
    get pos_path
    assert_select "summary", "Add transport"

    post pos_lines_path, params: { code: "CEM-50" }, as: :turbo_stream
    post pos_transport_path, params: { amount: "1500", destination: "Ruiru, Kamakis" }, as: :turbo_stream
    assert_select "#cart", /Transport · to Ruiru, Kamakis/

    sale = acme { shifts(:acme_front_open).current_sale }
    line = acme { sale.lines.find(&:transport?) }
    assert_equal [ 1500_00, 1500_00 ], [ line.unit_price_cents, line.total_cents ]

    acme { Current.set(account: @account, user: users(:carl)) { sale.change_customer(customers(:acme_contractor)) } }
    assert_equal 1500_00, acme { line.reload.unit_price_cents }, "the contractor's price list doesn't reprice transport"

    post pos_payments_path, params: { tender: "cash", tendered: "100000" }
    get new_delivery_note_path(sale_id: sale.id)
    assert_select ".hint", /Transport of KES 1,500.00 is already on the sale/
  end

  test "transport at the till needs an amount" do
    post pos_transport_path, params: { amount: "" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=update][target=pos_message] [role=alert]", /Enter what the transport costs/
  end

  test "a charge on a delivery note after the sale becomes a confirmed order for the customer" do
    sale = completed_sale(customer: customers(:acme_contractor))

    post delivery_notes_path, params: { delivery_note: { sale_id: sale.id, address: "Plot 9, Ruiru", transport_charge: "2000" } }
    note = acme { @account.delivery_notes.last }
    assert_redirected_to delivery_note_path(note)

    order = acme { note.transport_order }
    assert acme { order.ordered? }
    assert_equal customers(:acme_contractor), acme { order.customer }
    assert_equal [ [ "TRANSPORT", 2000_00, "#{acme { note.reference }} to Plot 9, Ruiru" ] ],
      acme { order.lines.map { [ _1.product.sku, _1.unit_price_cents, _1.detail ] } }

    follow_redirect!
    assert_select "#transport", /KES 2,000.00 · charged on order #{acme { order.reference }}/
    get delivery_note_path(note, format: :pdf)
    assert_equal "application/pdf", response.media_type

    post customer_order_collection_path(order)
    assert_redirected_to pos_path
    assert_equal [ [ "TRANSPORT", 2000_00 ] ], acme { shifts(:acme_front_open).current_sale.lines.map { [ _1.product.sku, _1.total_cents ] } }
  end

  test "a walk-in sale can't be charged afterwards, and no charge makes no order" do
    sale = completed_sale

    get new_delivery_note_path(sale_id: sale.id)
    assert_select ".hint", /add transport at the till before payment/

    post delivery_notes_path, params: { delivery_note: { sale_id: sale.id, address: "Gate C", transport_charge: "500" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", /needs a named customer/

    assert_no_difference -> { acme { CustomerOrder.count } } do
      post delivery_notes_path, params: { delivery_note: { sale_id: sale.id, address: "Gate C", transport_charge: "" } }
    end
    assert_nil acme { @account.delivery_notes.last.transport_order }
  end
end
