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

  # The WhatsApp button is a form that makes the link and opens WhatsApp in a new tab.
  def whatsapp_form
    form = css_select("form[action='#{document_shares_path}']").first or return
    form.css("input[type=hidden]").to_h { [ _1["name"], _1["value"] ] }
  end

  def press_whatsapp_button
    fields = whatsapp_form
    assert fields, "a WhatsApp button on #{request.path}"
    post document_shares_path, params: fields.except("authenticity_token")
    assert_response :redirect
    response.location
  end

  def shared_path_in(href)
    URI(Rack::Utils.parse_query(URI(href).query)["text"][%r{https?://\S+}]).path
  end

  test "a sale's WhatsApp button opens a chat with the customer, the receipt number and a link anyone can open" do
    sign_in_as users(:amina)
    get sale_path(@sale)
    assert_select "form[action=?][target=_blank]", document_shares_path

    href = press_whatsapp_button
    assert href.start_with?("https://wa.me/254722000111?"), href
    text = Rack::Utils.parse_query(URI(href).query)["text"]
    assert_match(/\AAcme Hardware: your receipt #{Account.without_isolation { @sale.receipt_number }} for KES [\d,.]+\. http/, text)
    assert Account.without_isolation { Event.exists?(action: "shared", eventable_type: "DocumentShare") }

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
      href = press_whatsapp_button
      get shared_path_in(href)
      assert_equal "application/pdf", response.media_type, page
    end
  end

  test "a link only opens its own document, at its own shop, for 30 days, and can be taken back" do
    share = Account.without_isolation { Current.set(account: accounts(:acme), user: users(:amina)) { DocumentShare.create_for!(@sale) } }

    use_account accounts(:acme)
    get share_path(share.token)
    assert_response :success
    assert_equal 1, Account.without_isolation { share.reload.opened_count }

    get share_path(share.token.succ)
    assert_response :not_found

    use_account accounts(:bolt)
    get share_path(share.token)
    assert_response :not_found

    use_account accounts(:acme)
    travel 31.days do
      get share_path(share.token)
      assert_response :not_found
      assert_match "expired", response.body
    end

    sign_in_as users(:amina)
    get sale_path(@sale)
    assert_select "#shared_links", /1 live link of 1/
    assert_select "##{dom_id(share)}", /opened 1 time/

    delete document_share_path(share), headers: { "Referer" => sale_url(@sale) }
    assert_redirected_to sale_url(@sale)
    get share_path(share.token)
    assert_response :not_found
    assert Account.without_isolation { Event.exists?(action: "share_revoked") }
  end

  test "a statement stays fixed to the period it was sent with" do
    customer = customers(:acme_contractor)
    sign_in_as users(:amina)
    get customer_statement_path(customer, from: "2026-10-01", to: "2026-10-31")
    href = press_whatsapp_button
    assert_match "#{I18n.l(Date.new(2026, 10, 1), format: :long)} to #{I18n.l(Date.new(2026, 10, 31), format: :long)}", Rack::Utils.parse_query(URI(href).query)["text"]

    share = Account.without_isolation { DocumentShare.last }
    assert_equal [ Date.new(2026, 10, 1), Date.new(2026, 10, 31) ], [ share.from, share.to ]

    travel 20.days do
      delete session_path
      get shared_path_in(href)
      assert_equal "application/pdf", response.media_type
    end
  end

  test "a share can't be made for another shop's document" do
    sign_in_as users(:bob), account: accounts(:bolt)
    post document_shares_path, params: { kind: "receipt", id: @sale.id }
    assert_response :not_found
    assert_equal 0, Account.without_isolation { DocumentShare.count }
  end
end
