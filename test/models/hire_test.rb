require "test_helper"

class HireTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:acme)
    Current.account = @account
    Current.session = @account.sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @main = branches(:acme_main)
    @mixer = @account.hire_items.create!(branch: @main, name: "Concrete mixer", asset_tag: "mix-01", daily_rate: "1500", weekly_rate: "6000", deposit: "5000")
    @compactor = @account.hire_items.create!(branch: @main, name: "Plate compactor", asset_tag: "CMP-01", daily_rate: "2500", deposit: "8000")
  end

  def hire(items = [ @mixer ], out: Time.current, back: out + 3.days)
    HireAgreement.hire_out(branch: @main, customer: customers(:acme_contractor), items: items, started_at: out, due_back_at: back,
      id_number: "12345678", site: "Plot 12, Kitengela")
  end

  test "charges by the day, capped at the weekly rate, with an hour's grace" do
    now = Time.current
    assert_equal 1, HireLine.days_between(now, now + 1.hour)
    assert_equal 1, HireLine.days_between(now, now + 25.hours)
    assert_equal 2, HireLine.days_between(now, now + 25.hours + 1.minute)

    charge = ->(days) { HireLine.charge_for(days, daily_cents: 1500_00, weekly_cents: 6000_00) }
    assert_equal [ 4500_00, 6000_00, 6000_00, 7500_00, 12000_00, 12000_00 ], [ 3, 5, 7, 8, 13, 14 ].map(&charge)
    assert_equal 10 * 2500_00, HireLine.charge_for(10, daily_cents: 2500_00)
  end

  test "hiring out takes the tools off the shelf and opens an order with the estimate" do
    agreement = hire([ @mixer, @compactor ])
    assert agreement.persisted?, agreement.errors.full_messages.to_sentence
    assert_equal "#{@main.code}-H00001", agreement.reference
    assert [ @mixer, @compactor ].all? { _1.reload.on_hire? }
    assert_equal 13000_00, agreement.deposit_due_cents

    order = agreement.customer_order
    assert_equal [ "ordered", "hire" ], [ order.status, order.source ]
    assert_equal 3 * 1500_00 + 3 * 2500_00, order.total_cents
    assert_match "Concrete mixer MIX-01, 3 days (estimate)", order.lines.first.description
    assert_not order.collectable?, "not settled while the tools are out"
    assert_not order.editable?
  end

  test "a tool that's out, or at another branch, can't be hired" do
    hire
    again = hire
    assert_match "Concrete mixer MIX-01 isn't available", again.errors.full_messages.to_sentence

    @compactor.update!(branch: branches(:acme_yard))
    assert_match "isn't available at Main", hire([ @compactor ]).errors.full_messages.to_sentence
  end

  test "tools come back one at a time; when the last is back the order has the actual charges" do
    out = 5.days.ago
    agreement = hire([ @mixer, @compactor ], out: out, back: out + 3.days)
    mixer_line, compactor_line = agreement.lines

    agreement.return_tools({ mixer_line.id => { condition_note: "Fine" } }, at: out + 2.days + 30.minutes)
    assert agreement.reload.out?
    assert @mixer.reload.available?
    assert_equal [ 2, 3000_00 ], [ mixer_line.reload.days_charged, mixer_line.charge_cents ]

    agreement.return_tools({ compactor_line.id => { damage: "1200", damage_note: "Bent handle", needs_repair: "1" } }, at: out + 5.days)
    assert agreement.reload.returned?
    assert @compactor.reload.maintenance?

    order = agreement.customer_order.reload
    assert order.ready?
    assert_equal [ "Tool hire · Concrete mixer MIX-01, 2 days", "Tool hire · Plate compactor CMP-01, 5 days", "Tool hire · Damage to Plate compactor CMP-01: Bent handle" ],
      order.lines.map(&:description)
    assert_equal 3000_00 + 5 * 2500_00 + 1200_00, order.total_cents
    assert_equal 5 * 2500_00 + 1200_00, @compactor.earned_cents
  end

  test "settled at the till like an order: the deposit counts and the receipt says what was hired" do
    agreement = hire(out: 2.days.ago, back: 1.day.from_now)
    order = agreement.customer_order
    order.take_deposit(amount_cents: 5000_00, tender: "cash", shift: @shift)
    assert_not order.load_into(@shift.current_sale), "tools still out"

    agreement.return_tools({ agreement.lines.first.id => {} })
    sale = @shift.current_sale
    assert order.reload.load_into(sale), order.errors.full_messages.to_sentence
    assert_equal "Tool hire · Concrete mixer MIX-01, 2 days", sale.lines.sole.description
    assert_equal 3000_00, sale.reload.total_cents

    sale.pay(tender: "deposit")
    assert sale.reload.completed?
    assert order.reload.collected?
    assert_equal 2000_00, order.deposit_balance_cents, "the rest of the deposit is left to refund"
  end

  test "extending moves the due time and the estimate" do
    agreement = hire
    assert agreement.extend_to(agreement.due_back_at + 4.days)
    assert_equal 6000_00, agreement.customer_order.reload.total_cents, "7 days at the weekly rate"
    assert_not agreement.extend_to(1.day.ago)
  end

  test "a hire made by mistake is cancelled and the tools go back on the shelf" do
    agreement = hire
    assert agreement.cancel
    assert @mixer.reload.available?
    assert agreement.customer_order.reload.cancelled?
  end

  test "overdue hires, and a daily reminder text" do
    @account.update!(sms_enabled: true)
    agreement = hire(out: 4.days.ago, back: 1.day.ago)
    assert_includes @account.hire_agreements.overdue, agreement

    assert agreement.remind
    assert_match "was due back", Sms::Message.last.body
    assert_not agreement.remind, "once a day"
  end
end
