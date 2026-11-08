require "test_helper"

class Pos::OfflineControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  test "the catalogue snapshot has the till, retail prices, packs, barcodes and stock, and isn't sent again unchanged" do
    get pos_catalogue_path, as: :json
    assert_response :success
    catalogue = response.parsed_body

    assert_equal [ "Front counter", shifts(:acme_front_open).id, users(:carl).id ], catalogue["till"].values_at("register_name", "shift_id", "cashier_id")
    nails = catalogue["products"].find { _1["sku"] == "NAIL-3" }
    assert_equal [ 25000, 16.0, 25.5, true ], nails.values_at("price_cents", "tax_rate", "stock", "fractional")
    screws = catalogue["products"].find { _1["sku"] == "SCR-815" }
    assert_equal "6001234500012", screws["packs"].sole["barcodes"].sole
    assert_not catalogue.to_s.include?("cost"), "costs stay on the server"

    get pos_catalogue_path, as: :json, headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
  end

  test "offline sales are sent with a fresh form token and each gets an answer" do
    get new_pos_offline_sale_path, as: :json
    token = response.parsed_body["token"]
    assert token.present?

    uuid = SecureRandom.uuid
    sale = { uuid: uuid, receipt_number: "MAIN-OFF1-0001", happened_at: 5.minutes.ago.iso8601, shift_id: shifts(:acme_front_open).id, cashier_id: users(:carl).id,
             total_cents: 25000, lines: [ { product_id: products(:acme_nails).id, quantity: "1", unit_price_cents: 25000 } ], payments: [ { tender: "cash", tendered_cents: 30000 } ] }
    2.times { post pos_offline_sales_path, params: { sales: [ sale ] }, as: :json, headers: { "X-CSRF-Token" => token } }

    result = response.parsed_body["results"].sole
    assert_equal [ uuid, "duplicate", "MAIN-000001" ], result.values_at("uuid", "status", "receipt_number")
  end

  test "the offline till page and the installable app" do
    get pos_offline_path
    assert_select "[data-controller=offline-till]"
    assert_select "body[data-offline-sync-offline-page-value=true]"

    get pwa_manifest_path(format: :json)
    assert_equal "/pos", JSON.parse(response.body)["start_url"]
    assert_equal "application/manifest+json", response.media_type
    get pwa_service_worker_path(format: :js)
    assert_match "const OFFLINE_TILL = \"/pos/offline\"", response.body
    assert_equal "no-cache", response.headers["Cache-Control"]
  end

  test "receipts as data for the receipt printer" do
    sale = Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        shifts(:acme_front_open).current_sale.tap { _1.add(products(:acme_nails), quantity: 2) }.tap { _1.pay(tender: "cash", tendered_cents: 100000) }
      end
    end

    get sale_receipt_path(sale, format: :json)
    receipt = response.parsed_body
    assert_equal [ "Acme Hardware", "MAIN-000001", "KES 500.00", "KES 500.00", true ], receipt.values_at("header", "receipt_number", "total", "change", "open_drawer").flatten.values_at(0, 3, 4, 5, 6)
    assert_equal "2 kg x 250.00", receipt["lines"].sole["detail"]
  end

  test "QZ Tray gets the shop's own certificate and signatures, and drawer openings are recorded" do
    get qz_certificate_path
    assert_response :success
    certificate = OpenSSL::X509::Certificate.new(response.body)
    assert_equal "/CN=acme.localhost/O=Acme Hardware", certificate.subject.to_s
    assert_equal certificate.subject, certificate.issuer, "self-signed while the platform has no QZ certificate"
    assert_not_includes response.body, Account::QzSigning::INTERMEDIATE_MARKER

    post qz_signature_path, params: { request: "to sign" }
    assert_response :forbidden, "only for a till that prints through QZ Tray"
    Account.without_isolation { registers(:acme_front).update_columns(print_mode: "qz_tray", printer_name: "EPSON") }
    post qz_signature_path, params: { request: "to sign" }
    assert certificate.public_key.verify(OpenSSL::Digest.new("SHA512"), Base64.decode64(response.body), "to sign")
    assert_not Account.without_isolation { accounts(:bolt).qz_public_key }.verify(OpenSSL::Digest.new("SHA512"), Base64.decode64(response.body), "to sign"),
      "another shop's QZ Tray doesn't trust this shop's signatures"

    post pos_drawer_openings_path
    assert_response :no_content
    assert_equal "drawer_opened", Account.without_isolation { registers(:acme_front).events.last.action }
  end

  test "with a QZ-issued platform certificate, each shop's certificate is issued under it and sent with it" do
    platform_key = OpenSSL::PKey::RSA.new(2048)
    platform = OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version, cert.serial = 2, 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=HardPoint/O=HardPoint")
      cert.public_key, cert.not_before, cert.not_after = platform_key.public_key, Time.current - 1.day, Time.current + 1.year
      cert.sign(platform_key, OpenSSL::Digest.new("SHA256"))
    end
    Rails.configuration.x.qz = { certificate: platform.to_pem, private_key: platform_key.to_pem }

    get qz_certificate_path
    shop_pem, platform_pem = response.body.split("#{Account::QzSigning::INTERMEDIATE_MARKER}\n")
    shop = OpenSSL::X509::Certificate.new(shop_pem)
    assert_equal platform.subject, shop.issuer
    assert shop.verify(platform_key), "issued by the platform's key"
    assert_equal platform.to_pem.strip, platform_pem.strip
  ensure
    Rails.configuration.x.qz = nil
  end

  test "a till printing through QZ Tray needs its printer's name" do
    register = Account.without_isolation { registers(:acme_front) }
    register.print_mode = "qz_tray"
    assert_not register.valid?
    register.printer_name = "EPSON TM-T20III"
    assert register.valid?
  end
end
