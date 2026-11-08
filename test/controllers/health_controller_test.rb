require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "the monitor gets 200 and the checks' names, and the details only with the token" do
    get health_path, headers: { "Host" => "localhost" }
    assert_response :ok
    assert_equal "ok", response.parsed_body["status"]
    assert_equal "ok", response.parsed_body.dig("checks", "database")

    with_env("HEALTH_TOKEN" => "secret-token") do
      get health_path(token: "wrong")
      assert_equal "ok", response.parsed_body.dig("checks", "database"), "no details for a wrong token"

      get health_path(token: "secret-token")
      assert_equal "primary answers", response.parsed_body.dig("checks", "database", "detail")
    end
  end

  test "a failing check answers 503" do
    Account.without_isolation do
      Current.set(account: accounts(:acme), user: users(:amina)) do
        accounts(:acme).account_backups.create!(kind: "manual", status: "failed", requested_by: users(:amina), failure: "bucket said no")
      end
    end

    use_account accounts(:acme)
    get health_path
    assert_response :service_unavailable
    assert_equal "failing", response.parsed_body["status"]
    assert_equal "failing", response.parsed_body.dig("checks", "backups")
  end

  private
    def with_env(values)
      previous = values.keys.index_with { ENV[_1] }
      values.each { ENV[_1] = _2 }
      yield
    ensure
      previous.each { ENV[_1] = _2 }
    end
end
