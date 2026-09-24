# Requests to the public API on api.localhost with a shop's key.
class ApiTestCase < ActionDispatch::IntegrationTest
  setup { host! "api.localhost" }

  def api_key_for(account, scope: "write", name: "Test key")
    Account.without_isolation { Current.set(account: account) { account.api_keys.create!(name: name, scope: scope) } }
  end

  def headers_for(key, **extra)
    { "Authorization" => "Bearer #{key.token}", "Content-Type" => "application/json" }.merge(extra)
  end

  def api_get(path, key: @key, **params) = get(path, params: params, headers: headers_for(key))
  def api_post(path, body, key: @key, **headers) = post(path, params: body.to_json, headers: headers_for(key, **headers))
  def api_patch(path, body, key: @key) = patch(path, params: body.to_json, headers: headers_for(key))

  def json = response.parsed_body
  def error_code = json.dig("error", "code")
end
