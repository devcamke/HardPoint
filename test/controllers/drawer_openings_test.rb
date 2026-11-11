require "test_helper"

# Opening the cash drawer without a sale: why, recorded, and seen on the shift, in the report and the morning email.
class DrawerOpeningsTest < ActionDispatch::IntegrationTest
  setup do
    Account.without_isolation { registers(:acme_front).update_columns(print_mode: "qz_tray", printer_name: "EPSON") }
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  def in_acme(&) = Account.without_isolation { Current.set(account: accounts(:acme)) { yield } }

  test "the till asks why, and the reason is kept with the shift" do
    get pos_path
    assert_select "details[data-controller=receipt-printer] button[data-receipt-printer-reason-param]", Pos::DrawerOpeningsController::REASONS.size

    post pos_drawer_openings_path, params: { reason: "Change for a customer" }
    post pos_drawer_openings_path, params: { reason: "anything else" }
    assert_response :no_content
    reasons = in_acme { registers(:acme_front).events.where(action: "drawer_opened").order(:id).map { _1.particulars["reason"] } }
    assert_equal [ "Change for a customer", "No sale" ], reasons
    assert_equal shifts(:acme_front_open).id, in_acme { registers(:acme_front).events.last.particulars["shift_id"] }

    get shift_path(shifts(:acme_front_open))
    assert_select "p", /Drawer opened without a sale: 2/
    assert_select "span", "Change for a customer"
  end

  test "the discounts and voids report counts each cashier's openings" do
    post pos_drawer_openings_path, params: { reason: "Checking the float" }
    report = in_acme { Report::DiscountsAndVoids.new(account: accounts(:acme), period: Report::Period.new(from: Date.current, to: Date.current)) }
    by_cashier = in_acme { report.sections.first }
    assert_equal "Drawer opened, no sale", by_cashier.columns.last.label
    assert_equal 1, by_cashier.rows.find { _1.first == users(:carl).name }.last
    assert_equal 1, by_cashier.totals.last
  end
end
