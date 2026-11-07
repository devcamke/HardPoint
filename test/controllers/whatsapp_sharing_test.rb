require "test_helper"

class WhatsappSharingTest < ActionDispatch::IntegrationTest
  setup do
    @sale = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        shifts(:acme_front_open).current_sale.tap do |sale|
          sale.change_customer(customers(:acme_contractor))
          sale.add(products(:acme_nails))
          sale.pay(tender: "cash")
        end
      end
    end
  end

  def whatsapp_link
    css_select("a[href^='https://wa.me/']").first&.[]("href")
  end

  def shared_path_in(href)
    URI(Rack::Utils.parse_query(URI(href).query)["text"][%r{https?://\S+}]).path
  end

  test "a sale's WhatsApp button opens a chat with the customer, the receipt number and a link anyone can open" do
    sign_in_as users(:amina)
    get sale_path(@sale)

    href = whatsapp_link
    assert href.start_with?("https://wa.me/254722000111?"), href
    text = Rack::Utils.parse_query(URI(href).query)["text"]
    assert_match(/\AAcme Hardware: your receipt #{Account.without_isolation { @sale.receipt_number }} for KES [\d,.]+\. http/, text)

    delete session_path
    get shared_path_in(href)
    assert_response :success
    assert_select ".receipt", /#{Account.without_isolation { @sale.receipt_number }}/
  end

  test "quotes, statements, purchase orders and delivery notes open as PDFs" do
    sign_in_as users(:amina)
    records = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:amina)) do
        quote = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
          lines_attributes: [ { account: accounts(:acme), product_code: "CEM-50", quantity: 2 } ])
        po = accounts(:acme).purchase_orders.create!(supplier: suppliers(:acme_cement_distributor), branch: branches(:acme_main),
          lines_attributes: [ { account: accounts(:acme), product: products(:acme_cement), quantity: 10, unit_cost_cents: 68_000 } ])
        note = accounts(:acme).delivery_notes.create!(sale: @sale, branch: branches(:acme_main), address: "Site 4, Ruiru")
        [ quote, po, note ]
      end
    end

    [ customer_order_path(records[0]), customer_statement_path(customers(:acme_contractor)), purchase_order_path(records[1]),
      delivery_note_path(records[2]) ].each do |page|
      get page
      assert whatsapp_link, "a WhatsApp button on #{page}"
      get shared_path_in(whatsapp_link)
      assert_equal "application/pdf", response.media_type, page
    end
  end

  test "a link only opens its own document, at its own shop, for 30 days" do
    token = Account.without_isolation { DocumentShare.token_for(@sale) }

    use_account accounts(:acme)
    get share_path(token)
    assert_response :success

    get share_path(token.succ)
    assert_response :not_found

    use_account accounts(:bolt)
    get share_path(token)
    assert_response :not_found

    use_account accounts(:acme)
    travel 31.days do
      get share_path(token)
      assert_response :not_found
      assert_match "expired", response.body
    end
  end
end
