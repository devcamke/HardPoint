require "test_helper"

# Settings › Appearance and Settings › Shop preferences, and the places each choice shows up.
class ShopCustomisationTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)
  def account = acme { accounts(:acme).reload }

  test "choosing a preset theme repaints every screen, and a colour too light for white text is refused" do
    sign_in_as users(:amina)
    get edit_appearance_path
    assert_select "input[name=theme][value=teal][checked]"
    assert_select "style", text: /--color-primary/, count: 0, message: "the default theme needs no overrides"

    patch appearance_path, params: { theme: "blue", receipt_stamp: "1" }
    assert_redirected_to edit_appearance_path
    assert_equal "#1D4ED8", account.theme_color
    get settings_path
    assert_select "style", /--color-primary-500: #1D4ED8;/
    assert_select "meta[name=theme-color][content='#1D4ED8']"

    patch appearance_path, params: { theme: "custom", custom_color: "#FDE68A", receipt_stamp: "1" }
    assert_response :unprocessable_entity
    assert_match "too light", response.body
    assert_equal "#1D4ED8", account.theme_color

    patch appearance_path, params: { theme: "custom", custom_color: "#5B21B6", receipt_stamp: "1" }
    assert_equal "#5B21B6", account.theme_color
  end

  test "a logo is kept and shown, and anything but a picture is refused" do
    sign_in_as users(:amina)
    patch appearance_path, params: { theme: "teal", receipt_stamp: "1", logo: fixture_file_upload("signed-note.png", "image/png") }
    assert_redirected_to edit_appearance_path
    assert acme { account.logo.attached? }

    patch appearance_path, params: { theme: "teal", receipt_stamp: "1", logo: fixture_file_upload("notes.txt", "text/plain") }
    assert_response :unprocessable_entity
    assert_match "must be a PNG, JPEG or WebP picture", response.body

    patch appearance_path, params: { theme: "teal", receipt_stamp: "1", remove_logo: "1" }
    perform_enqueued_jobs
    assert_not acme { account.logo.attached? }
  end

  test "only those who manage the shop change its look and preferences" do
    sign_in_as users(:carl)
    get edit_appearance_path
    assert_response :forbidden
    patch preferences_path, params: { account: { quote_validity_days: "30" } }
    assert_response :forbidden
  end

  test "preferences are saved, checked, and used: quotes, new customers, the till's payment buttons" do
    sign_in_as users(:amina)
    patch preferences_path, params: { account: { quote_validity_days: "30", customer_payment_terms_days: "14", dead_stock_days: "60",
      expiry_warning_days: "45", reorder_lookback_days: "60", supplier_lead_time_days: "10", till_tenders: [ "mobile_money", "on_account" ],
      payment_details: "Paybill 123456", document_terms: "Goods remain ours until paid." } }
    assert_redirected_to edit_preferences_path
    saved = account
    assert_equal [ 30, 14, 60, 45, 60, 10, [ "mobile_money", "on_account" ], "Paybill 123456" ],
      [ saved.quote_validity_days, saved.customer_payment_terms_days, saved.dead_stock_days, saved.expiry_warning_days,
        saved.reorder_lookback_days, saved.supplier_lead_time_days, saved.till_tenders, saved.payment_details ]

    patch preferences_path, params: { account: { quote_validity_days: "0", dead_stock_days: "5" } }
    assert_response :unprocessable_entity
    assert_match "How long a quote is valid must be a whole number from 1 to 365", response.body

    acme do
      Current.set(account: accounts(:acme)) do
        quote = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
          lines_attributes: [ { product: products(:acme_nails), quantity: 1 } ])
        assert_equal Date.current + 30, quote.valid_until
        assert_equal 14, accounts(:acme).customers.new(name: "New").payment_terms_days
      end
    end

    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: acme { registers(:acme_front) }.id }
    post pos_lines_path, params: { code: "SCR-815" }, as: :turbo_stream
    get pos_path
    assert_select "input[name=tender][value=cash]"
    assert_select "input[name=tender][value=mobile_money]"
    assert_select "input[name=tender][value=card]", count: 0
  end

  test "the receipt's stamp can be left off" do
    acme { accounts(:acme).update!(receipt_stamp: false) }
    sign_in_as users(:amina)
    get onboarding_test_receipt_path
    assert_response :success
    assert_select "svg.stamp", count: 0
  end

  test "quotes carry the logo, the theme colour, how to pay and the terms" do
    acme do
      Current.set(account: accounts(:acme)) do
        quote = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
          lines_attributes: [ { product: products(:acme_nails), quantity: 1 } ])
        plain = CustomerOrderPdf.new(quote).render

        accounts(:acme).update!(theme_color: "#B91C1C", payment_details: "M-Pesa Paybill 123456", document_terms: "Goods remain ours until paid for.")
        accounts(:acme).logo.attach(io: file_fixture("signed-note.png").open, filename: "logo.png", content_type: "image/png")
        branded = CustomerOrderPdf.new(quote.reload).render

        assert branded.start_with?("%PDF")
        assert_operator branded.bytesize, :>, plain.bytesize + 1000, "the logo and the notes are drawn"
        assert_includes branded, "0.72549 0.1098 0.1098 scn", "titles in the shop's colour"
      end
    end
  end
end
