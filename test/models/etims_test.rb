require "test_helper"

class EtimsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    Current.account = accounts(:acme)
    Current.session = @session = accounts(:acme).sessions.create!(user: users(:carl))
    @kra = fake_transport(Etims::Client,
      "/etims-api/selectInitOsdcInfo" => { resultCd: "000", data: { info: { cmcKey: "CMCKEY123", sdcId: "KRACU0300000001", mrcNo: "WIS01000001" } } },
      "/etims-api/saveItem" => { resultCd: "000", resultMsg: "It is succeeded" },
      "/etims-api/saveTrnsSalesOsdc" => ->(request) {
        { resultCd: "000", data: { curRcptNo: request.json[:invcNo], totRcptNo: request.json[:invcNo], intrlData: "INTERNALDATA", rcptSign: "SIGNATURE1234567",
                                   sdcDateTime: "20260924101500" } } })
    @device = accounts(:acme).etims_devices.create!(branch: branches(:acme_main), environment: "sandbox", tin: "P051234567X", serial_number: "HP-MAIN-01")
    @device.initialize_with_kra
    @shift = shifts(:acme_front_open)
  end

  # Jobs run inline reset Current when they finish, as they would in a worker; the test carries on as the cashier.
  def transmitting(&)
    perform_enqueued_jobs(only: Etims::TransmitJob, &)
  ensure
    Current.account = accounts(:acme)
    Current.session = @session
  end

  def sell(product, quantity: 1, discount_cents: 0)
    sale = @shift.current_sale
    sale.add(product, quantity: quantity)
    if discount_cents.positive?
      sale.update!(discount_cents: discount_cents)
      sale.recalculate
    end
    transmitting { sale.pay(tender: "card", reference: "VISA 1") }
    sale.reload
  end

  test "setting up the control unit stores KRA's communication key, encrypted" do
    assert_equal "CMCKEY123", @device.reload.cmc_key
    assert_equal "KRACU0300000001", @device.sdc_id
    raw = ActiveRecord::Base.connection.select_value("SELECT cmc_key FROM etims_devices WHERE id = #{@device.id}")
    assert_not_includes raw, "CMCKEY123"
    assert_equal({ "tin" => "P051234567X", "bhfId" => "00" }, @kra.last("/etims-api/selectInitOsdcInfo").headers)
  end

  test "a completed sale is registered, sent and signed" do
    sale = sell(products(:acme_nails), quantity: 4, discount_cents: 10000)
    submission = sale.etims_submission

    assert submission.sent?
    assert_equal 1, submission.invoice_number
    assert_equal "SIGNATURE1234567", submission.receipt_signature
    assert_equal "https://etims-sbx.kra.go.ke/common/link/etims/receipt/indexEtimsReceiptData?Data=P051234567X00SIGNATURE1234567", submission.verification_url

    sent = @kra.last("/etims-api/saveTrnsSalesOsdc")
    assert_equal "CMCKEY123", sent.headers["cmcKey"]
    assert_equal "S", sent.json[:rcptTyCd]
    assert_equal "05", sent.json[:pmtTyCd], "card"
    assert_equal 900.0, sent.json[:totAmt], "1,000.00 less the 100.00 cart discount"
    assert_equal 900.0, sent.json[:taxblAmtB]
    assert_equal (90000 * 16 / 116.0).round / 100.0, sent.json[:taxAmtB]
    item = sent.json[:itemList].sole
    assert_equal [ 250.0, 1000.0, 100.0, 900.0 ], item.values_at(:prc, :splyAmt, :dcAmt, :totAmt)
    assert_equal "B", item[:taxTyCd]
    assert_equal Etims::Item.code_for(products(:acme_nails)), @kra.last("/etims-api/saveItem").json[:itemCd]
  end

  test "each item is registered once per control unit" do
    sell(products(:acme_nails))
    sell(products(:acme_nails))

    assert_equal 1, @kra.requests.count { _1.path == "/etims-api/saveItem" }
  end

  test "voids and returns go as credit notes against the original invoice" do
    voided = sell(products(:acme_nails))
    transmitting { voided.void(reason: "Rang up twice", by: users(:amina)) }
    void_note = accounts(:acme).etims_submissions.find_by!(document: voided, kind: "credit_note")
    assert void_note.sent?
    assert_equal [ "R", 1, "13" ], @kra.last("/etims-api/saveTrnsSalesOsdc").json.values_at(:rcptTyCd, :orgInvcNo, :rfdRsnCd)

    sale = sell(products(:acme_nails), quantity: 2)
    transmitting do
      accounts(:acme).sale_returns.create!(sale: sale, shift: @shift, refund_method: "cash", approver: users(:amina),
        lines_attributes: [ { sale_line: sale.lines.first, quantity: 1, restock: true } ])
    end
    returned = @kra.last("/etims-api/saveTrnsSalesOsdc").json
    assert_equal [ "R", sale.etims_submission.invoice_number, "06", "01", 250.0 ], returned.values_at(:rcptTyCd, :orgInvcNo, :rfdRsnCd, :pmtTyCd, :totAmt)
  end

  test "while KRA can't be reached, sending is retried with growing gaps" do
    fake_transport(Etims::Client, "/etims-api/saveItem" => JsonHttp::Unreachable.new("timed out"))
    sale = sell(products(:acme_nails))
    submission = sale.etims_submission

    assert submission.pending?
    assert_match "couldn't be reached", submission.last_error
    assert_not submission.due_for_retry?
    travel 3.minutes do
      assert submission.due_for_retry?
    end
  end

  test "a refusal waits for someone to fix it and retry" do
    fake_transport(Etims::Client, "/etims-api/saveItem" => { resultCd: "891", resultMsg: "Item class code does not exist" })
    submission = sell(products(:acme_nails)).etims_submission

    assert submission.failed?
    assert_equal "891: Item class code does not exist", submission.last_error
    assert_not submission.due_for_retry?

    fake_transport(Etims::Client, "/etims-api/saveItem" => { resultCd: "000" }, "/etims-api/saveTrnsSalesOsdc" => { resultCd: "000", data: { rcptSign: "OK" } })
    transmitting { submission.retry_now }
    assert submission.reload.sent?
  end

  test "branches without a control unit, and sales from before, aren't sent" do
    @device.update!(active: false)
    sale = sell(products(:acme_nails))
    assert_nil sale.etims_submission

    @device.update!(active: true)
    transmitting { sale.void(reason: "Wrong", by: users(:amina)) }
    assert_empty accounts(:acme).etims_submissions
  end

  test "tax types come from the shop's tax rates, with KRA's usual ones by default" do
    tax_rates(:acme_zero).update!(etims_code: "A")
    assert_equal "A", Etims.tax_type_for(accounts(:acme), 0)
    assert_equal "B", Etims.tax_type_for(accounts(:acme), 16)
    assert_equal "E", Etims.tax_type_for(accounts(:acme), 8)
  end
end
