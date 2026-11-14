require "test_helper"

class EtimsPurchasesTest < ActionDispatch::IntegrationTest
  setup do
    acme do
      @device = accounts(:acme).etims_devices.create!(branch: branches(:acme_main), environment: "simulator", tin: "P051234567X", serial_number: "HP-1")
      @device.initialize_with_kra
      suppliers(:acme_cement_distributor).update!(tax_pin: "P051999888Z")
    end
  end

  def acme(&block) = Account.without_isolation { Current.set(account: accounts(:acme), &block) }
  def purchases = acme { accounts(:acme).etims_purchases.order(:id).to_a }

  test "checking KRA lists what suppliers have invoiced, under Buy" do
    sign_in_as users(:amina)
    get etims_purchases_path
    assert_select "p.hint", /Nothing waiting/
    assert_select "nav a[href=?]", etims_purchases_path, "From KRA"

    post etims_purchases_check_path
    assert_redirected_to etims_purchases_path
    assert_equal "2 new invoices from KRA.", flash[:notice]
    follow_redirect!
    assert_select "td", /Nairobi Cement Distributors/
    assert_select "td span.badge", "new supplier"

    post etims_purchases_check_path
    assert_equal "Nothing new from KRA.", flash[:notice]
  end

  test "receiving from the invoice's page, with a line left out" do
    sign_in_as users(:amina)
    post etims_purchases_check_path
    purchase = purchases.first

    get etims_purchase_path(purchase)
    assert_select "input[name='lines[1][product_code]'][value='CEM-50']"
    assert_select "input[type=submit][value=?]", "Receive into Main branch and record the invoice"

    assert_difference -> { acme { products(:acme_cement).stock_at(branches(:acme_main)) } }, 20 do
      post etims_purchase_receipt_path(purchase), params: { lines: { "1" => { product_code: "CEM-50", quantity: "20", unit_cost: "700.00" } } }
    end
    receipt = acme { purchase.reload.goods_receipt }
    assert_redirected_to receipt
    assert_match "invoice #{purchase.invoice_number} recorded", flash[:notice]

    get etims_purchase_path(purchase)
    assert_select "input[type=submit][value*=Receive]", count: 0
    assert_select "a[href=?]", goods_receipt_path(receipt)
  end

  test "a line that matches nothing sends the page back with what's wrong" do
    sign_in_as users(:amina)
    post etims_purchases_check_path
    stranger = purchases.last

    post etims_purchase_receipt_path(stranger), params: { lines: { "2" => { skip: "1" } } }
    assert_redirected_to stranger
    assert_match "Say which product “Transport to site” is", flash[:alert]

    post etims_purchase_invoice_path(stranger)
    supplier = acme { stranger.reload.supplier }
    assert_redirected_to supplier
    assert_equal "Rift Valley Steel Mills Ltd", supplier.name

    post etims_purchase_dismissal_path(stranger)
    assert_match "already been invoiced", flash[:alert]
  end

  test "setting aside and bringing back" do
    sign_in_as users(:amina)
    post etims_purchases_check_path
    purchase = purchases.first

    post etims_purchase_dismissal_path(purchase), params: { reason: "Duplicate" }
    assert_redirected_to etims_purchases_path
    get etims_purchases_path(status: "dismissed")
    assert_select "td a", purchase.invoice_number

    delete etims_purchase_dismissal_path(purchase)
    assert acme { purchase.reload.new? }
  end

  test "cashiers see none of it; a stock clerk receives but doesn't record invoices alone" do
    acme { Etims::Purchase.fetch(@device) }
    purchase = purchases.first

    sign_in_as users(:carl)
    get etims_purchases_path
    assert_response :forbidden
    post etims_purchase_receipt_path(purchase)
    assert_response :forbidden
  end

  test "without a control unit there's no From KRA in the menu" do
    acme { @device.update!(cmc_key: nil) }
    sign_in_as users(:amina)
    get etims_purchases_path
    assert_select "nav a[href=?]", etims_purchases_path, count: 0
    assert_select "a[href=?]", etims_devices_path
  end
end
