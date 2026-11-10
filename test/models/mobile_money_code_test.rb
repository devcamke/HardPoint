require "test_helper"

class MobileMoneyCodeTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:acme)
    @session = Account.without_isolation { @account.sessions.create!(user: users(:carl)) }
    @shortcode = within { @account.mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator") }
  end

  def within(&block)
    Account.without_isolation { Current.set(account: @account, session: @session, &block) }
  end

  def new_sale(product = products(:acme_nails), quantity: 4)
    within { shifts(:acme_front_open).current_sale.tap { _1.add(product, quantity: quantity) } }
  end

  def paid_to_paybill(code, shillings, bill_reference: nil)
    within do
      @shortcode.receive_c2b_confirmation("TransID" => code, "TransAmount" => shillings.to_s, "BillRefNumber" => bill_reference,
        "TransTime" => Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S"), "MSISDN" => "254722000111")
    end
  end

  test "a code typed at the till is used once" do
    sale = new_sale
    within { sale.pay(tender: "mobile_money", reference: "SJQ82KD91L") }
    assert within { sale.reload.completed? }

    second = new_sale
    payment = within { second.pay(tender: "mobile_money", reference: " sjq82kd91l ") }
    assert_not payment.persisted?
    assert_match(/M-Pesa code SJQ82KD91L was already used on sale #{within { sale.receipt_number }}/, payment.errors.full_messages.to_sentence)
  end

  test "a code Safaricom says was for less than the sale is refused; one for enough claims that money" do
    paid_to_paybill("SJQ82KD91L", 100)
    sale = new_sale
    due = within { sale.balance_due_cents }
    assert_operator due, :>, 100_00

    payment = within { sale.pay(tender: "mobile_money", reference: "SJQ82KD91L") }
    assert_match(/was for KES 100.00, less than/, payment.errors.full_messages.to_sentence)

    paid_to_paybill("SKA11PQ22R", due / 100 + 1)
    payment = within { sale.pay(tender: "mobile_money", reference: "SKA11PQ22R") }
    assert payment.persisted?
    assert_equal payment, within { @account.mpesa_transactions.find_by!(trans_id: "SKA11PQ22R").matched }
  end

  test "deposits and payments on account claim the money, and can't reuse a code" do
    paid_to_paybill("SDE11PQ22R", 500)
    quote = within { @account.customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor), lines_attributes: [ { product: products(:acme_nails), quantity: 2 } ]) }
    deposit = within { quote.take_deposit(amount_cents: 500_00, tender: "mobile_money", reference: "SDE11PQ22R") }
    assert deposit.persisted?
    assert_equal deposit, within { @account.mpesa_transactions.find_by!(trans_id: "SDE11PQ22R").matched }

    again = within { customers(:acme_contractor).customer_payments.create(account: @account, amount_cents: 500_00, payment_method: "mobile_money", reference: "SDE11PQ22R") }
    assert_not again.persisted?
    assert_match(/already used as a deposit on #{quote.reference}/, again.errors.full_messages.to_sentence)

    sale = new_sale
    payment = within { sale.pay(tender: "mobile_money", reference: "SDE11PQ22R") }
    assert_not payment.persisted?
  end

  test "a callback after a status check renames the money instead of recording it twice" do
    sale = new_sale
    request = within { sale.stk_requests.create!(account: @account, shortcode: @shortcode, phone: "254722000111", amount_cents: sale.balance_due_cents, checkout_request_id: "ws_CO_1234567890", requested_by: users(:carl)) }

    within { request.resolve(result_code: "0") } # the status check: paid, but no receipt number
    placeholder = within { @account.mpesa_transactions.sole }
    assert placeholder.trans_id.start_with?("STK")
    assert within { sale.reload.completed? }

    within { request.resolve(result_code: "0", receipt_number: "SKZ99AB12C", amount_cents: request.amount_cents) } # the callback
    assert_equal [ "SKZ99AB12C" ], within { @account.mpesa_transactions.pluck(:trans_id) }
    assert_equal "SKZ99AB12C", within { sale.payments.sole.reference }
    assert_equal "SKZ99AB12C", within { request.reload.receipt_number }
  end

  test "money for a prompt that arrives after the till stopped waiting marks the prompt paid" do
    sale = new_sale
    request = within { sale.stk_requests.create!(account: @account, shortcode: @shortcode, phone: "254722000111", amount_cents: sale.balance_due_cents, checkout_request_id: "ws_CO_0987654321", requested_by: users(:carl)) }
    within { request.update!(status: :expired) }

    within { request.resolve(result_code: "0", receipt_number: "SLT88XY77Z", amount_cents: request.amount_cents) }
    assert within { request.reload.paid? }
    assert within { sale.reload.completed? }
  end
end
