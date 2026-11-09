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
      sale.update!(discount_cents: discount_cents, discount_approver: users(:amina), approved_discount_percent: 100) # a manager's discount
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

  test "exempt and zero-rated lines, both 0%, go to KRA under their own tax types" do
    exempt = accounts(:acme).tax_rates.create!(name: "Exempt", rate: 0, etims_code: "A")
    tax_rates(:acme_zero).update!(etims_code: "C")
    products(:acme_nails).update!(tax_rate: exempt)        # 250.00 a kilo
    products(:acme_screws).update!(tax_rate: tax_rates(:acme_zero)) # 5.00 each

    sale = @shift.current_sale
    sale.add(products(:acme_nails), quantity: 4)
    sale.add(products(:acme_screws), quantity: 10)
    transmitting { sale.pay(tender: "card", reference: "VISA 1") }

    sent = @kra.last("/etims-api/saveTrnsSalesOsdc")
    assert_equal %w[ A C ], sent.json[:itemList].map { _1[:taxTyCd] }
    assert_equal [ 1000.0, 50.0, 0.0 ], sent.json.values_at(:taxblAmtA, :taxblAmtC, :taxblAmtB)
    assert_equal [ "A", "C" ], sale.reload.lines.order(:id).map { _1.tax_rate_record.etims_code }
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

  test "the invoice's totals are the receipt's, with the cart discount's odd cents on the last line" do
    sale = @shift.current_sale
    [ :acme_nails, :acme_cement, :acme_pipe ].each { sale.add(products(_1)) }
    sale.update!(discount_cents: 5, discount_approver: users(:amina), approved_discount_percent: 100)
    sale.recalculate
    transmitting { sale.pay(tender: "card", reference: "VISA 1") }
    sale.reload

    sent = @kra.last("/etims-api/saveTrnsSalesOsdc").json
    assert_equal sale.total_cents / 100.0, sent[:totAmt]
    assert_equal sale.tax_cents / 100.0, sent[:totTaxAmt]
    assert_equal sale.total_cents / 100.0, sent[:itemList].sum { _1[:totAmt] }.round(2)
    assert_equal sale.tax_cents / 100.0, sent[:taxAmtB]
  end

  test "a deposit taken on an earlier day doesn't decide the payment type when the balance was paid another way" do
    order = accounts(:acme).customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor),
      lines_attributes: [ { account: accounts(:acme), product_code: "NAIL-3", quantity: 4 } ])
    order.take_deposit(amount_cents: 900_00, tender: "cash", shift: @shift)
    sale = @shift.current_sale
    order.load_into(sale)
    sale.pay(tender: "deposit")
    transmitting { sale.pay(tender: "mobile_money", reference: "SJK4H7T2QR") }

    assert_equal "06", @kra.last("/etims-api/saveTrnsSalesOsdc").json[:pmtTyCd], "M-Pesa, not the larger deposit"
  end

  test "a customer's KRA PIN goes on the invoice only when it's a valid one" do
    customers(:acme_contractor).update!(tax_pin: " p051234567x ")
    assert_equal "P051234567X", customers(:acme_contractor).tax_pin
    sale = @shift.current_sale
    sale.update!(customer: customers(:acme_contractor))
    sale.add(products(:acme_nails))
    transmitting { sale.pay(tender: "card", reference: "VISA 1") }
    assert_equal "P051234567X", @kra.last("/etims-api/saveTrnsSalesOsdc").json[:custTin]

    customers(:acme_contractor).update_column(:tax_pin, "not a pin") # saved before PINs were checked
    sale = @shift.current_sale
    sale.update!(customer: customers(:acme_contractor))
    sale.add(products(:acme_nails))
    transmitting { sale.pay(tender: "card", reference: "VISA 1") }
    assert_nil @kra.last("/etims-api/saveTrnsSalesOsdc").json[:custTin]
  end

  test "a customer's tax PIN must look like a KRA PIN, or be left blank" do
    customer = customers(:acme_contractor)
    customer.tax_pin = "A 123 456 789 z"
    assert customer.valid?
    assert_equal "A123456789Z", customer.tax_pin

    customer.tax_pin = "123456789"
    assert_not customer.valid?
    assert_match "KRA PIN", customer.errors[:tax_pin].to_sentence

    customer.tax_pin = " "
    assert customer.valid?
    assert_nil customer.tax_pin
  end

  test "each item is registered once per control unit" do
    sell(products(:acme_nails))
    sell(products(:acme_nails))

    assert_equal 1, @kra.requests.count { _1.path == "/etims-api/saveItem" }
  end

  test "a product registered with KRA is registered again when its name or tax rate changes" do
    sell(products(:acme_nails))
    assert_equal 1, @kra.requests.count { _1.path == "/etims-api/saveItem" }

    perform_enqueued_jobs(only: Etims::ItemUpdateJob) { products(:acme_nails).update!(price_cents: 26000) }
    assert_equal 1, @kra.requests.count { _1.path == "/etims-api/saveItem" }, "the price isn't KRA's business"

    perform_enqueued_jobs(only: Etims::ItemUpdateJob) { products(:acme_nails).update!(name: "Wire nails 3in", tax_rate: tax_rates(:acme_zero)) }
    Current.account = accounts(:acme)
    registered = @kra.last("/etims-api/saveItem").json
    assert_equal [ "Wire nails 3in", "C", Etims::Item.code_for(products(:acme_nails)) ], registered.values_at(:itemNm, :taxTyCd, :itemCd)

    # KRA couldn't be reached: the next sale registers it instead.
    fake_transport(Etims::Client, "/etims-api/saveItem" => JsonHttp::Unreachable.new("timed out"))
    perform_enqueued_jobs(only: Etims::ItemUpdateJob) { products(:acme_nails).update!(name: "Wire nails 75mm") }
    Current.account = accounts(:acme)
    assert_not @device.item_registrations.exists?(product: products(:acme_nails))

    perform_enqueued_jobs(only: Etims::ItemUpdateJob) { products(:acme_screws).update!(name: "Screws") }
    assert_not @device.item_registrations.exists?(product: products(:acme_screws)), "never sold, so it registers on its first sale"
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

  test "a control unit sends one invoice at a time, in the order they were numbered" do
    first, second = 2.times.map { sell(products(:acme_nails)).etims_submission }
    other = accounts(:acme).etims_devices.create!(branch: branches(:acme_yard), environment: "sandbox", tin: "P051234567X", bhf_id: "01", serial_number: "HP-YARD-01")

    assert_equal Etims::TransmitJob.new(first).concurrency_key, Etims::TransmitJob.new(second).concurrency_key
    assert_not_equal Etims::TransmitJob.new(first).concurrency_key,
      Etims::TransmitJob.new(Etims::Submission.new(device: other)).concurrency_key
    assert_equal 1, Etims::TransmitJob.concurrency_limit
  end

  test "sales, voids and returns that were never queued for KRA are found and queued" do
    travel_to 1.hour.from_now.beginning_of_hour # clear of the control unit's set-up
    lost_sale = sell(products(:acme_nails))
    voided = sell(products(:acme_nails))
    transmitting { voided.void(reason: "Rang up twice", by: users(:amina)) }
    returned = sell(products(:acme_nails), quantity: 2)
    sale_return = transmitting do
      accounts(:acme).sale_returns.create!(sale: returned, shift: @shift, refund_method: "cash", approver: users(:amina),
        lines_attributes: [ { sale_line: returned.lines.first, quantity: 1, restock: true } ])
    end
    # The app stopped between saving each and queuing it.
    lost = [ lost_sale.etims_submission, Etims::Submission.find_by!(document: voided, kind: "credit_note"), Etims::Submission.find_by!(document: sale_return) ]
    lost.each(&:delete)
    just_now = sell(products(:acme_nails))
    just_now.etims_submission.delete

    travel 5.minutes do
      Etims::ReconcileJob.perform_now
      assert_nil just_now.reload.etims_submission, "only minutes old, it may still be on its way"
    end
    travel 20.minutes do
      transmitting { Etims::ReconcileJob.perform_now }
    end
    Current.account = accounts(:acme)

    assert lost_sale.reload.etims_submission.sent?
    assert Etims::Submission.find_by!(document: voided, kind: "credit_note").sent?
    assert Etims::Submission.find_by!(document: sale_return, kind: "credit_note").sent?
    assert just_now.reload.etims_submission.sent?
    assert_no_difference -> { Etims::Submission.count } do
      travel(30.minutes) { Etims::ReconcileJob.perform_now }
    end
  end

  test "sales from while the control unit was switched off aren't swept up when it's switched on" do
    travel_to 1.hour.from_now
    @device.update!(active: false)
    sale = sell(products(:acme_nails))
    travel 1.minute
    @device.update!(active: true)

    travel(1.hour) { Etims::ReconcileJob.perform_now }
    Current.account = accounts(:acme)
    assert_nil sale.reload.etims_submission
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
