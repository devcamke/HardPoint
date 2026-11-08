require "test_helper"

class BillingTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:amina))
    @account.update!(trial_ends_at: 10.days.from_now)
  end

  test "plans limit branches, tills and staff, never products" do
    @account.update!(plan: "starter")

    branch = Branch.create(name: "Third branch")
    assert_match "Your Starter plan allows 1 branch. Add branches or upgrade on the Billing page", branch.errors.full_messages.to_sentence
    till = Register.create(branch: branches(:acme_main), name: "Back office")
    assert_match "allows 2 tills", till.errors.full_messages.to_sentence
    spare = Register.create(branch: branches(:acme_main), name: "Spare", active: false)
    assert spare.persisted?, spare.errors.full_messages.to_sentence
    product = Product.create(name: "Yet another screw", sku: "SCR-9999", unit: units(:acme_piece), price_cents: 100)
    assert product.persisted?, product.errors.full_messages.to_sentence

    @account.update!(plan: "enterprise")
    third = Branch.create(name: "Third branch")
    assert third.persisted?, third.errors.full_messages.to_sentence
  end

  test "an extra till or branch bought as an add-on makes room and goes on the invoice" do
    @account.update!(plan: "starter")
    assert_not Register.create(branch: branches(:acme_main), name: "Back office").persisted?

    assert @account.change_add_ons(extra_registers: 1)
    assert_equal 3, @account.limit(:registers)
    till = Register.create(branch: branches(:acme_main), name: "Back office")
    assert till.persisted?, till.errors.full_messages.to_sentence
    assert_equal 2_500_00 + 750_00, @account.monthly_price_cents
    assert_equal "add_ons_changed", @account.events.last.action

    assert_not @account.change_add_ons(extra_registers: 0), "the extra till is in use"
    assert_match "more than 2 tills in use", @account.errors.full_messages.to_sentence
    assert_equal 1, @account.reload.extra_registers

    invoice = @account.start_subscription_now
    assert_equal [ 3_250_00, 1, "monthly" ], [ invoice.amount_cents, invoice.extra_registers, invoice.interval ]
    assert_equal [ [ "HardPoint Starter plan", 1, 2_500_00 ], [ "Extra till × 1", 1, 750_00 ] ], invoice.lines
    assert_match "Starter plan and add-ons, a month from", invoice.description
  end

  test "a smaller plan only if what's in use fits it, counting add-ons; Enterprise drops them" do
    assert_not @account.change_plan("starter")
    assert_match "Starter allows 1 branch;", @account.errors.full_messages.to_sentence

    @account.update!(extra_branches: 1)
    assert @account.change_plan("starter"), @account.errors.full_messages.to_sentence
    assert_equal "plan_changed", @account.events.last.action

    assert @account.change_plan("enterprise")
    assert_equal 0, @account.extra_branches
    assert_not @account.change_add_ons(extra_registers: 1)
    assert_match "no limits", @account.errors.full_messages.to_sentence
    assert @account.change_add_ons(billing_interval: "yearly")
  end

  test "yearly billing: one invoice for twelve months at ten months' price" do
    @account.update!(billing_interval: "yearly")

    travel_to 11.days.from_now do
      @account.bill
      invoice = @account.open_invoice
      assert_equal [ 65_000_00, "yearly", invoice.period_start + 1.year ], [ invoice.amount_cents, invoice.interval, invoice.period_end ]
      assert_equal [ [ "HardPoint Business plan", 12, 65_000_00 ] ], invoice.lines
      assert_match "a year from", invoice.description

      invoice.payments.create!(account: @account, provider: "manual", amount_cents: invoice.amount_cents, reference: "EFT-Y").succeed(receipt: "EFT-Y")
      assert_equal invoice.period_end, @account.reload.current_period_ends_at.in_time_zone(@account.time_zone).to_date
    end

    travel_to 200.days.from_now do
      @account.bill
      assert_equal 1, @account.billing_invoices.count, "nothing more is billed during the year"
    end
  end

  test "a one-off invoice is paid like any other, locks the shop when overdue, and leaves the subscription alone" do
    invoice = @account.issue_one_off_invoice("Setup and training visit", 15_000_00)
    assert invoice.one_off?
    assert_equal [ "Setup and training visit", Date.current + 7 ], [ invoice.description, invoice.due_on ]
    assert_equal [ [ "Setup and training visit", nil, 15_000_00 ] ], invoice.lines
    assert @account.trialing?

    travel_to 8.days.from_now do
      @account.bill
      assert @account.reload.read_only?
    end

    assert @account.record_manual_payment("EFT-SETUP")
    assert @account.reload.trialing?, "paid, the shop is back to its trial"
    assert_nil @account.current_period_ends_at

    travel_to 11.days.from_now do
      @account.bill
      assert_equal 6_500_00, @account.open_invoice.amount_cents, "the trial still ends with a normal first invoice"
    end
  end

  test "trial reminder, first invoice at the end of the trial, reminder, then read-only" do
    travel_to 8.days.from_now do
      assert_enqueued_email_with BillingMailer, :trial_ending, params: { account: @account } do
        @account.bill
      end
      assert_no_enqueued_emails { @account.bill }
    end

    travel_to 11.days.from_now do
      @account.bill
      invoice = @account.open_invoice
      assert_match(/\AHP-\d{4}-\d{6}\z/, invoice.number)
      assert_equal [ 6_500_00, "business", Date.current + 7 ], [ invoice.amount_cents, invoice.plan, invoice.due_on ]
      assert @account.reload.payment_due?
    end

    travel_to 16.days.from_now do
      assert_enqueued_emails(1) { @account.bill }
      assert @account.open_invoice.reminded_at
    end

    travel_to 19.days.from_now do
      @account.bill
      assert @account.reload.read_only?
      assert @account.locked?
    end
  end

  test "paying the invoice makes the shop active until the month's end, and the next month bills again" do
    travel_to 11.days.from_now do
      @account.bill
      invoice = @account.open_invoice
      payment = invoice.payments.create!(account: @account, provider: "manual", amount_cents: invoice.amount_cents, reference: "EFT-1")

      assert payment.succeed(receipt: "EFT-1")
      assert invoice.reload.paid?
      assert @account.reload.active?
      assert_equal invoice.period_end, @account.current_period_ends_at.in_time_zone(@account.time_zone).to_date
      assert_not payment.succeed(receipt: "EFT-1"), "paid once"
    end

    travel_to 42.days.from_now do
      @account.bill
      assert @account.reload.payment_due?
      assert_equal 2, @account.billing_invoices.count
    end
  end

  test "a payment short of the invoice doesn't pay it" do
    invoice = @account.start_subscription_now
    payment = invoice.payments.create!(account: @account, provider: "mpesa", amount_cents: invoice.amount_cents, reference: "ws_CO_9")

    assert_not payment.succeed(receipt: "X", amount_cents: 100_00)
    assert payment.failed?
    assert invoice.reload.open?
  end

  test "paying by M-Pesa prompt on HardPoint's own Paybill" do
    daraja = fake_transport(Mpesa::Client, "/oauth/v1/generate" => { access_token: "t" },
      "/mpesa/stkpush/v1/processrequest" => { CheckoutRequestID: "ws_CO_BILL", ResponseCode: "0" })
    Rails.configuration.x.billing_mpesa = { environment: "sandbox", shortcode: "600900", passkey: "pk", consumer_key: "k", consumer_secret: "s", callback_token: "secret-token" }

    invoice = @account.start_subscription_now
    payment = Billing::MpesaShortcode.new.request_payment(invoice: invoice, phone: "254722000111")
    assert_equal "ws_CO_BILL", payment.reference
    assert_equal [ 6500, invoice.number.delete("-") ], daraja.last("/mpesa/stkpush/v1/processrequest").json.values_at(:Amount, :AccountReference)

    Current.reset
    Billing::MpesaShortcode.new.receive_stk_callback("Body" => { "stkCallback" => { "CheckoutRequestID" => "ws_CO_BILL", "ResultCode" => 0,
      "CallbackMetadata" => { "Item" => [ { "Name" => "Amount", "Value" => 6500 }, { "Name" => "MpesaReceiptNumber", "Value" => "SKB1234567" } ] } } })

    Account.without_isolation do
      assert invoice.reload.paid?
      assert_equal "SKB1234567", payment.reload.receipt
    end
  ensure
    Rails.configuration.x.billing_mpesa = nil
  end

  test "a card checkout through Paystack, confirmed by verification" do
    Rails.configuration.x.paystack_secret_key = "sk_test_123"
    paystack = fake_transport(Billing::Paystack,
      "/transaction/initialize" => { status: true, data: { authorization_url: "https://checkout.paystack.com/abc" } },
      "/transaction/verify/HP-REF" => { status: true, data: { status: "success", amount: 6_500_00, currency: "KES" } })

    invoice = @account.start_subscription_now
    payment = invoice.payments.create!(account: @account, provider: "paystack", amount_cents: invoice.amount_cents, reference: "HP-REF")

    assert_equal "https://checkout.paystack.com/abc", Billing::Paystack.new.checkout_url(payment, email: "a@b.c", callback_url: "https://x/return")
    assert_equal "Bearer sk_test_123", paystack.requests.first.headers["Authorization"]
    assert_equal [ 6_500_00, "KES" ], paystack.requests.first.json.values_at(:amount, :currency)
    assert_equal [ "success", 6_500_00, "KES" ], Billing::Paystack.new.verify("HP-REF")
  ensure
    Rails.configuration.x.paystack_secret_key = nil
  end

  test "a checkout address that isn't Paystack's is refused" do
    Rails.configuration.x.paystack_secret_key = "sk_test_123"
    fake_transport(Billing::Paystack, "/transaction/initialize" => { status: true, data: { authorization_url: "https://evil.example/pay" } })
    invoice = @account.start_subscription_now
    payment = invoice.payments.create!(account: @account, provider: "paystack", amount_cents: invoice.amount_cents, reference: "HP-REF2")

    assert_raises(Billing::Paystack::Refused) { Billing::Paystack.new.checkout_url(payment, email: "a@b.c", callback_url: "https://x/return") }
  ensure
    Rails.configuration.x.paystack_secret_key = nil
  end

  test "the invoice PDF is on HardPoint's letterhead" do
    invoice = @account.start_subscription_now
    assert Billing::InvoicePdf.new(invoice).render.start_with?("%PDF")
  end
end
