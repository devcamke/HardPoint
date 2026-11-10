require "test_helper"

class FundisControllerTest < ActionDispatch::IntegrationTest
  def acme(&) = Account.without_isolation(&)
  # Fixtures are read under row-level security, so outside a shop they're read without it.
  def mason = @mason ||= acme { fundis(:acme_mason) }
  def category(name) = acme { categories(name) }

  setup do
    acme { accounts(:acme).update!(fundi_commission_percent: 2) }
  end

  test "the cashier names the fundi at the till, and the paid sale earns their commission" do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }

    get pos_fundis_path, params: { query: "0711 222" }
    assert_select "button", /Otieno Ouma/
    assert_select "button", text: /Kariuki/, count: 0 # inactive

    patch pos_fundi_path, params: { fundi_id: mason.id }, as: :turbo_stream
    assert_match "Brought by Otieno Ouma", response.body
    post pos_lines_path, params: { code: "SCR-815", quantity: 10 }, as: :turbo_stream
    post pos_payments_path, params: { tender: "cash", tendered: "100" }, as: :turbo_stream

    acme do
      sale = accounts(:acme).sales.completed.order(:completed_at).last
      assert_equal mason, sale.fundi
      assert_equal ((sale.total_cents - sale.tax_cents) * 0.02).round, mason.balance_cents
    end
  end

  test "the fundis list, a fundi's statement, and adding one from the till" do
    sign_in_as users(:carl)
    get fundis_path
    assert_select "a", "Otieno Ouma"
    assert_select "a", text: "Commission rates", count: 0, message: "rates are for owners and managers"

    get fundi_path(mason)
    assert_select "h2", "Statement"

    post fundis_path, params: { for_till: 1, fundi: { name: "Achieng Tiler", phone: "0722 111 000", trade: "tiler", commission_percent: "9" } }
    assert_redirected_to pos_path
    acme { assert_nil accounts(:acme).fundis.find_by!(name: "Achieng Tiler").commission_percent, "a cashier can't set a fundi's own rate" }
  end

  test "only owners and managers set rates and pay commission" do
    sign_in_as users(:carl)
    get edit_fundi_rates_path
    assert_response :forbidden
    get new_fundi_payout_path(mason)
    assert_response :forbidden

    sign_in_as users(:amina)
    patch fundi_rates_path, params: { fundi_commission_percent: "2.5", categories: { category(:acme_fasteners).id => "4", category(:acme_plumbing).id => "" } }
    assert_redirected_to fundis_path
    acme do
      assert_equal 2.5, accounts(:acme).reload.fundi_commission_percent
      assert_equal 4, categories(:acme_fasteners).reload.fundi_commission_percent
      assert_nil categories(:acme_plumbing).reload.fundi_commission_percent
    end
  end

  test "paying a fundi by M-Pesa, and the commissions report" do
    acme do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).fundi_entries.create!(fundi: mason, kind: "earned", amount_cents: 500_00, sales_cents: 25_000_00, source: shifts(:acme_front_open), creator: users(:carl))
      end
    end
    sign_in_as users(:amina)

    post fundi_payouts_path(mason), params: { fundi_payout: { amount: "300", payment_method: "mobile_money", reference: "SGH12ABC34" } }
    assert_redirected_to fundi_path(mason)
    acme { assert_equal 200_00, mason.balance_cents }

    get report_path("fundi_commissions")
    assert_response :success
    assert_select "tbody tr:first-child" do
      assert_select "td", /Otieno Ouma/
      assert_select "td", /25,000\.00/
      assert_select "td", /200\.00/
    end
  end

  test "the report is listed only while fundi commissions are switched on" do
    sign_in_as users(:amina)
    get reports_path
    assert_select "a[href='#{report_path("fundi_commissions")}']"

    acme { accounts(:acme).update!(features: Account::Features::KEYS - [ "fundis" ]) }
    get reports_path
    assert_select "a[href='#{report_path("fundi_commissions")}']", count: 0
  end
end
