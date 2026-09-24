require "test_helper"

class ReportsControllerTest < ActionDispatch::IntegrationTest
  test "owners see every report on screen, as CSV and as PDF" do
    sign_in_as users(:amina)

    get reports_path
    assert_response :success

    Report::KEYS.each do |key|
      get report_path(key, preset: "this_month")
      assert_response :success, key
      get report_path(key, preset: "last_week", format: :csv)
      assert_equal "text/csv", response.media_type, key
      get report_path(key, from: "2026-01-01", to: "2026-01-31", branch_id: branches(:acme_main).id, format: :pdf)
      assert response.body.start_with?("%PDF"), key
    end

    get report_path("sales", by: "product")
    assert_select "select[name=by] option[selected]", "Product"
    get report_path("nope")
    assert_response :not_found
  end

  test "cashiers and stock clerks don't see reports or the owner's dashboard" do
    sign_in_as users(:carl)
    get report_path("sales")
    assert_response :forbidden

    get root_path
    assert_select "turbo-cable-stream-source", 0
    assert_select "nav a", text: "Reports", count: 0
  end

  test "the owner's dashboard is live and can focus on a branch" do
    sign_in_as users(:amina)

    get root_path(branch_id: branches(:acme_main).id)
    assert_select "h1", "Today at Main branch"
    assert_select "turbo-cable-stream-source[channel=DashboardChannel]"
    assert_select "meta[name=turbo-refresh-method][content=morph]"
  end

  test "completing a sale refreshes open dashboards" do
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:carl)) do
        sale = shifts(:acme_front_open).current_sale
        sale.add(products(:acme_nails))

        assert_turbo_stream_broadcasts [ accounts(:acme), :dashboard ] do
          perform_enqueued_jobs { sale.pay(tender: "cash") }
        end
      end
    end
  end

  test "turning the daily summary off and on" do
    sign_in_as users(:amina)

    patch my_daily_summary_path, params: { daily_summary: "false" }
    assert_not Account.without_isolation { memberships(:amina_acme).reload.daily_summary? }
    patch my_daily_summary_path, params: { daily_summary: "true" }
    assert Account.without_isolation { memberships(:amina_acme).reload.daily_summary? }
  end
end
