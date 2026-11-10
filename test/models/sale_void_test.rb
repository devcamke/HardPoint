require "test_helper"

class SaleVoidTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:acme)
    @session = Account.without_isolation { @account.sessions.create!(user: users(:carl)) }
    @shift = shifts(:acme_front_open)
    @customer = customers(:acme_contractor)
  end

  def within(&block)
    Account.without_isolation { Current.set(account: @account, session: @session, &block) }
  end

  def sale_for(customer = nil)
    within do
      @shift.current_sale.tap do |sale|
        sale.update!(customer: customer) if customer
        sale.add(products(:acme_cement), quantity: 2)
      end
    end
  end

  test "a cash refund on a void hands back only the cash paid, not what went on account" do
    sale = sale_for(@customer)
    within { sale.pay(tender: "cash", amount_cents: 500_00, tendered_cents: 500_00); sale.pay(tender: "on_account") }
    balance = within { @customer.reload.balance_cents }
    expected = within { @shift.expected_cash_cents_now }

    assert within { sale.void(reason: "Rang up twice", by: users(:amina), refund_method: "cash") }
    assert_equal 500_00, within { sale.void_refund_cents }
    assert_equal expected - 500_00, within { @shift.expected_cash_cents_now }
    assert_equal balance - (sale.total_cents - 500_00), within { @customer.reload.balance_cents }, "the part on account no longer counts"
  end

  test "a void credited to the customer's account shows on their account and statement" do
    sale = sale_for(@customer)
    within { sale.pay(tender: "cash", tendered_cents: 2_000_00) }
    balance = within { @customer.reload.balance_cents }

    assert within { sale.void(reason: "Wrong items", by: users(:amina), refund_method: "on_account") }
    assert_equal balance - sale.total_cents, within { @customer.reload.balance_cents }

    entry = within { Customer::Statement.new(@customer.reload, from: 1.month.ago, to: Date.current).entries.last }
    assert_equal [ "Voided sale credited", 0, sale.total_cents ], [ entry.description, entry.charge_cents, entry.credit_cents ]
  end

  test "M-Pesa handed back in cash stays money received on the M-Pesa report" do
    shortcode = within { @account.mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator") }
    within do
      shortcode.receive_c2b_confirmation("TransID" => "SJQ82KD91L", "TransAmount" => "1600", "MSISDN" => "254722000111",
        "TransTime" => Time.current.in_time_zone("Nairobi").strftime("%Y%m%d%H%M%S"))
    end
    sale = sale_for
    within { sale.pay(tender: "mobile_money", reference: "SJQ82KD91L") }

    assert within { sale.void(reason: "Wrong items", by: users(:amina), refund_method: "cash") }
    assert_nil within { @account.mpesa_transactions.find_by!(trans_id: "SJQ82KD91L").refunded_at }
  end
end
