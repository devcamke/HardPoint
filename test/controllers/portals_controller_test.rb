require "test_helper"

# The customer portal: a contractor opens their account from a link, without signing in, and pays with M-Pesa.
class PortalsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @customer = customers(:acme_contractor) # +254722000111, 30 days' terms
    in_acme do
      accounts(:acme).update!(features: accounts(:acme).features + [ "customer_portal" ])
      @shortcode = accounts(:acme).mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator")
      stock_up products(:acme_nails), 50
      @sale = account_sale(quantity: 4) # 1,000.00, 40 days ago, so overdue
      @link = PortalLink.for(@customer)
    end
    use_account accounts(:acme)
  end

  def in_acme(&) = Account.without_isolation { Current.set(account: accounts(:acme), user: users(:carl)) { yield } }

  def account_sale(quantity:)
    sale = shifts(:acme_front_open).current_sale
    sale.change_customer(@customer)
    sale.add(products(:acme_nails), quantity: quantity)
    assert sale.pay(tender: "on_account").persisted?
    sale.update_columns(completed_at: 40.days.ago)
    sale
  end

  test "the customer sees what they owe, what's overdue, and their invoices and statements, without signing in" do
    get portal_path(@link.token)
    assert_response :success
    assert_select "h1", /You owe/
    assert_select "p", /KES 1,000.00 of it is overdue/
    assert_select "a[href=?]", portal_invoice_path(@link.token, @sale), text: @sale.receipt_number
    assert_select "form[action=?] input[name=phone][value=?]", portal_payments_path(@link.token), "0722 000 111"
    assert_select "p", /Or pay from the M-Pesa menu: Paybill 174379, account 0722000111/
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_equal 1, in_acme { @link.reload.opened_count }

    get portal_invoice_path(@link.token, @sale)
    assert_equal "application/pdf", response.media_type
    get portal_statement_path(@link.token, period: "last_3_months")
    assert_equal "application/pdf", response.media_type
  end

  test "only this customer's own documents open" do
    other = in_acme do
      walk_in = shifts(:acme_front_open).current_sale
      walk_in.add(products(:acme_nails), quantity: 1)
      walk_in.pay(tender: "cash", tendered_cents: 1000_00)
      walk_in
    end
    get portal_invoice_path(@link.token, other)
    assert_response :not_found
  end

  test "paying with M-Pesa puts the money on the account, oldest invoice first" do
    post portal_payments_path(@link.token), params: { phone: "0722 000 111", amount: "600" }
    stk_request = in_acme { Mpesa::StkRequest.last }
    assert_redirected_to portal_payment_path(@link.token, stk_request)
    assert_equal [ @customer, nil, 600_00 ], in_acme { [ stk_request.customer, stk_request.sale, stk_request.amount_cents ] }

    follow_redirect!
    assert_select "h1", "Check your phone"
    assert_select "meta[http-equiv=refresh]"

    post portal_payments_path(@link.token), params: { phone: "0722 000 111", amount: "600" }
    follow_redirect!
    assert_select "[role=alert]", /already waiting/

    perform_enqueued_jobs(only: Mpesa::SimulatedCallbackJob)
    get portal_payment_path(@link.token, stk_request)
    assert_select "h1", "Paid, thank you"

    payment = in_acme { stk_request.reload.customer_payment }
    assert_equal [ 600_00, "mobile_money", @customer.id ], [ payment.amount_cents, payment.payment_method, payment.customer_id ]
    assert_equal 400_00, in_acme { @customer.reload.balance_cents }
  end

  test "a prompt the customer cancels takes nothing" do
    post portal_payments_path(@link.token), params: { phone: "0711 110 000", amount: "1000" } # the simulator's "cancel" number
    perform_enqueued_jobs(only: Mpesa::SimulatedCallbackJob)
    follow_redirect!
    assert_select "h1", "Not paid"
    assert_equal 1000_00, in_acme { @customer.reload.balance_cents }
  end

  test "a link opens only at its own shop" do
    use_account accounts(:bolt)
    get portal_path(@link.token)
    assert_response :not_found
    get portal_invoice_path(@link.token, @sale)
    assert_response :not_found
  end

  test "a link taken back, expired, or at a shop that switched the portal off opens nothing" do
    in_acme { @link.revoke }
    get portal_path(@link.token)
    assert_response :not_found
    assert_select "h1", "This link no longer opens"

    fresh = in_acme { PortalLink.for(@customer) }
    travel 91.days do
      get portal_path(fresh.token)
      assert_response :not_found
    end

    in_acme { accounts(:acme).update!(features: accounts(:acme).features - [ "customer_portal" ]) }
    get portal_path(fresh.token)
    assert_response :not_found
  end

  test "staff send the link on WhatsApp from the customer's page, or take it back" do
    sign_in_as users(:amina)
    get customer_path(@customer)
    assert_select "#portal input[value=?]", @link.url

    post customer_portal_link_path(@customer, send: "whatsapp")
    assert_match %r{\Ahttps://wa\.me/254722000111\?text=}, response.location
    assert_includes CGI.unescape(response.location), @link.url, "the same link again, not a new one"

    delete customer_portal_link_path(@customer)
    assert_not in_acme { @link.reload.active? }
  end

  test "cashiers, who don't handle accounts, can't hand out links" do
    sign_in_as users(:carl)
    post customer_portal_link_path(@customer)
    assert_response :forbidden
    assert_equal 1, in_acme { @customer.portal_links.count }
  end
end
