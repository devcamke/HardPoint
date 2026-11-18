require "test_helper"

# Goods rung up and taken off again before payment (a sale cleared, a line removed, a quantity cut) are kept, and
# seen on the shift, in Activity and in the report.
class Pos::TakenOffTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:carl)
    post pos_till_path, params: { register_id: registers(:acme_front).id }
    in_acme { stock_up products(:acme_nails), 100 }
  end

  def in_acme(&) = Account.without_isolation { Current.set(account: accounts(:acme)) { yield } }
  def taken_off = in_acme { registers(:acme_front).events.where(action: Sale::TakenOff::ACTIONS).order(:id).to_a }
  def ring_up(quantity) = post(pos_lines_path, params: { product_id: products(:acme_nails).id, quantity: quantity })
  def line = in_acme { shifts(:acme_front_open).current_sale.lines.sole }

  test "clearing a sale keeps what was in it, who cleared it and its value" do
    ring_up 5
    total = in_acme { shifts(:acme_front_open).current_sale.total_cents }
    assert_operator total, :>, 0

    post pos_discard_path
    event = taken_off.sole
    assert_equal [ "sale_cleared", users(:carl), total ], [ event.action, event.creator, event.particulars["value"] ]
    assert_equal [ "5 × #{products(:acme_nails).name}" ], event.particulars["items"]
    assert_equal shifts(:acme_front_open).id, event.particulars["shift_id"]
  end

  test "clearing an empty sale records nothing" do
    get pos_path
    post pos_discard_path
    assert_empty taken_off
  end

  test "removing a line and cutting a quantity are kept; raising a quantity isn't" do
    ring_up 5
    each = line.total_cents / 5

    patch pos_line_path(line), params: { sale_line: { quantity: 8 } }
    assert_empty taken_off

    patch pos_line_path(line), params: { sale_line: { quantity: 2 } }
    cut = taken_off.sole
    assert_equal [ "quantity_reduced", "8", "2", each * 6 ], [ cut.action, cut.particulars["from"], cut.particulars["to"], cut.particulars["value"] ]

    delete pos_line_path(line)
    removed = taken_off.last
    assert_equal [ "line_removed", "2 × #{products(:acme_nails).name}", each * 2 ], [ removed.action, removed.particulars["item"], removed.particulars["value"] ]
  end

  test "the shift, Activity and the report show them" do
    ring_up 5
    total = in_acme { shifts(:acme_front_open).current_sale.total_cents }
    post pos_discard_path

    get shift_path(shifts(:acme_front_open))
    assert_select "p", /Rung up, then taken off before payment: 1/
    assert_select "span", /Carl Cashier cleared a sale: 5 × #{Regexp.escape(products(:acme_nails).name)}/

    sign_in_as users(:amina)
    get events_path
    assert_match(/cleared a sale: 5 × #{Regexp.escape(products(:acme_nails).name)} \(.+\) on #{registers(:acme_front).name}, before payment/, response.body)

    report = in_acme { Report::DiscountsAndVoids.new(account: accounts(:acme), period: Report::Period.new(from: Date.current, to: Date.current)) }
    by_cashier, listed = in_acme { report.sections.values_at(0, -1) }
    assert_equal [ "Taken off before payment", "Taken off value" ], by_cashier.columns[8, 2].map(&:label)
    assert_equal [ 1, total ], by_cashier.rows.find { _1.first == users(:carl).name }[8, 2]
    assert_equal [ 1, total ], by_cashier.totals[8, 2]
    assert_equal [ users(:carl).name, registers(:acme_front).name, total ], listed.rows.sole.values_at(1, 2, 4)
  end
end
