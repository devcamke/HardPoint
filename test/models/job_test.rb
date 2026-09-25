require "test_helper"

class JobTest < ActiveSupport::TestCase
  setup do
    Current.account = accounts(:acme)
    Current.session = accounts(:acme).sessions.create!(user: users(:carl))
    @shift = shifts(:acme_front_open)
    @job = Current.account.jobs.create!(customer: customers(:acme_contractor), name: "Kamau residence", reference: "LPO 2291", site: "Kitengela", budget: "10000")
  end

  def sell(job: @job, items: { products(:acme_nails) => 4 })
    sale = @shift.current_sale
    sale.change_customer(job.customer)
    sale.update!(job: job)
    items.each { |product, quantity| sale.add(product, quantity: quantity) }
    sale.pay(tender: "card", reference: "VISA 1")
    sale.reload
  end

  test "spend counts completed sales less returns, against the budget" do
    sale = sell
    assert_equal sale.total_cents, @job.spent_cents
    assert_equal 10000_00 - sale.total_cents, @job.budget_left_cents
    assert_equal "Kamau residence (LPO 2291)", @job.label

    Current.account.sale_returns.create!(sale: sale, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: sale.lines.first, quantity: 1, restock: true } ])
    assert_equal sale.total_cents - sale.total_cents / 4, @job.spent_cents

    spent = @job.spent_cents
    assert sell.void(reason: "Wrong job", by: users(:amina))
    assert_equal spent, @job.spent_cents, "voided sales don't count"
  end

  test "materials add up product by product, net of returns" do
    first = sell(items: { products(:acme_nails) => 2, products(:acme_cement) => 1 })
    sell(items: { products(:acme_nails) => 3 })
    Current.account.sale_returns.create!(sale: first, shift: @shift, refund_method: "cash", approver: users(:amina),
      lines_attributes: [ { sale_line: first.lines.find_by(product: products(:acme_cement)), quantity: 1, restock: true } ])

    materials = @job.materials
    assert_equal [ products(:acme_nails) ], materials.map(&:product)
    assert_equal 5, materials.sole.quantity
    assert_equal Job.spent_cents_by_id([ @job.id ])[@job.id], @job.spent_cents
  end

  test "a sale's job must be the customer's, and open" do
    other = Current.account.customers.create!(name: "Someone else")
    sale = @shift.current_sale
    sale.change_customer(other)
    assert_not sale.update(job: @job)
    assert_match "customer's jobs", sale.errors.full_messages.to_sentence
    sale.reload

    @job.close
    sale.change_customer(customers(:acme_contractor))
    assert_not sale.update(job: @job)
    assert_match "closed", sale.errors.full_messages.to_sentence
    sale.reload
    assert @job.reopen
    assert sale.update(job: @job)

    sale.change_customer(other)
    assert_nil sale.job, "changing the customer drops their job"
  end

  test "a quote for a job carries it to the till" do
    order = Current.account.customer_orders.create!(branch: branches(:acme_main), customer: customers(:acme_contractor), job: @job,
      lines_attributes: [ { account: Current.account, product_code: "NAIL-3", quantity: 2 } ])
    sale = @shift.current_sale
    assert order.load_into(sale)
    assert_equal @job, sale.reload.job
  end

  test "names are unique per customer and budgets optional" do
    assert_not Current.account.jobs.new(customer: customers(:acme_contractor), name: " Kamau  residence ").valid?
    assert Current.account.jobs.new(customer: customers(:acme_contractor), name: "Borehole").valid?
    assert_nil Current.account.jobs.create!(customer: customers(:acme_contractor), name: "Shop fit-out", budget: "").budget_left_cents
  end

  test "the cost summary renders" do
    sell
    pdf = JobPdf.new(@job)
    assert pdf.render.start_with?("%PDF")
    assert_equal "mwangi-builders-ltd-kamau-residence-costs.pdf", pdf.filename
  end
end
