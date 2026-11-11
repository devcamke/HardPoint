require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Shops live on subdomains (acme.localhost); Chrome sends every *.localhost to this machine.
  Capybara.server_host = "127.0.0.1"
  Capybara.always_include_port = true

  def visit_shop(account, path = "/")
    Capybara.app_host = "http://#{account.subdomain}.localhost"
    visit path
  end

  def visit_public(path = "/")
    Capybara.app_host = "http://localhost"
    visit path
  end

  def sign_in_with_browser(user, account: accounts(:acme))
    visit_shop account, "/session/new"
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_no_current_path "/session/new"
  end

  teardown { Capybara.app_host = nil }
end
