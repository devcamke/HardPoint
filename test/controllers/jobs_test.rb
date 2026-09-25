require "test_helper"
require_relative "api/api_test_case"

class JobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:acme)
    sign_in_as users(:amina), account: @account
    post pos_till_path, params: { register_id: registers(:acme_front).id }
  end

  def acme(&) = Account.without_isolation(&)

  test "add a job, buy for it at the till, see what it cost" do
    get new_job_path(customer_id: customers(:acme_contractor).id)
    assert_response :success

    post jobs_path, params: { job: { customer_id: customers(:acme_contractor).id, name: "Kamau residence", reference: "LPO 2291", site: "Kitengela", budget: "50,000" } }
    job = acme { @account.jobs.last }
    assert_redirected_to job_path(job)
    assert_equal 50_000_00, acme { job.budget_cents }

    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream
    assert_select "select[name=job_id] option", text: "Kamau residence (LPO 2291)"
    patch pos_job_path, params: { job_id: job.id }, as: :turbo_stream
    assert_select "turbo-stream[target=pos_message]", /For Kamau residence \(LPO 2291\) · KES 50,000.00 of budget left/
    post pos_lines_path, params: { code: "NAIL-3" }, as: :turbo_stream
    post pos_payments_path, params: { tender: "card", reference: "VISA 1" }, as: :turbo_stream
    sale = acme { @account.sales.completed.last }
    assert_equal job, acme { sale.job }

    get job_path(job)
    assert_select "h1", /Kamau residence/
    assert_select "section", /Wire nails/
    assert_select "a", text: acme { sale.receipt_number }

    get jobs_path
    assert_select "##{dom_id(job)}", /Mwangi Builders/

    get job_summary_path(job)
    assert_equal "application/pdf", response.media_type

    get sale_receipt_path(sale)
    assert_match "Job: Kamau residence", response.body

    post job_closure_path(job)
    assert acme { job.reload.closed? }
    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream
    assert_select "select[name=job_id]", count: 0
    delete job_closure_path(job)
    assert acme { job.reload.open? }
  end

  test "a quote made from a job is for that job" do
    job = acme { Current.set(account: @account) { @account.jobs.create!(customer: customers(:acme_contractor), name: "Borehole") } }
    get new_customer_order_path(job_id: job.id)
    assert_select "select[name='customer_order[job_id]'] option[selected]", text: "Borehole"

    post customer_orders_path, params: { customer_order: { customer_id: customers(:acme_contractor).id, job_id: job.id, branch_id: branches(:acme_main).id,
      lines_attributes: { "0" => { product_code: "NAIL-3", quantity: 2 } } } }
    order = acme { @account.customer_orders.last }
    assert_equal job, acme { order.job }
  end

  test "another shop's job can't be picked at the till" do
    bolt_job = acme { Current.set(account: accounts(:bolt)) { accounts(:bolt).jobs.create!(customer: customers(:bolt_customer), name: "Theirs") } }
    patch pos_customer_path, params: { customer_id: customers(:acme_contractor).id }, as: :turbo_stream
    patch pos_job_path, params: { job_id: bolt_job.id }, as: :turbo_stream
    assert_response :not_found
  end
end

class Api::JobsTest < ApiTestCase
  test "jobs with their spend, and sales filtered by job" do
    acme = accounts(:acme)
    key = api_key_for(acme)
    job = Account.without_isolation { Current.set(account: acme) { acme.jobs.create!(customer: customers(:acme_contractor), name: "Kamau residence", budget: "1000") } }

    api_get api_v1_jobs_path, key: key, customer_id: customers(:acme_contractor).id
    assert_equal [ [ "Kamau residence", 1000_00, 0 ] ], response.parsed_body["data"].map { _1.values_at("name", "budget_cents", "spent_cents") }

    api_get api_v1_job_path(job), key: key
    assert_equal "open", response.parsed_body["status"]

    api_get api_v1_sales_path, key: key, job_id: job.id
    assert_equal [], response.parsed_body["data"]
  end
end
