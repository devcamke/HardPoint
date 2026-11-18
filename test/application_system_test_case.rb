require "test_helper"
require "net/http"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Chrome's password manager is off. After a sign-in it offers to save the password, or warns that "password" has
  # been in a data breach, in a bubble that takes the window's focus; the next click only closes the bubble and never
  # reaches the page. It shows once per browser, so only the first test of a run that signs in and then clicks lost
  # a click to it.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_preference "credentials_enable_service", false
    options.add_preference "profile.password_manager_enabled", false
    options.add_preference "profile.password_manager_leak_detection", false
  end

  # Shops live on subdomains (acme.localhost); Chrome sends every *.localhost to this machine.
  Capybara.server_host = "127.0.0.1"
  Capybara.always_include_port = true

  # One request at a time. A test's browser and server share a single database connection, and which shop that
  # connection may see is a setting on the connection (Account::Isolation). Two requests at once (Turbo prefetches a
  # link the mouse happens to rest on) can clear it under each other: the second then finds no session and is sent
  # to sign in. Each request has a connection of its own outside tests.
  Capybara.server = :puma, { Threads: "1:1" }

  # Jobs are kept, not run on a background thread behind the browser's back; a test runs the ones it means to.
  include ActiveJob::TestHelper

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

  # A journey is one task a person does from start to finish (test/system/journeys). Each step of it leaves a numbered
  # screenshot in tmp/journeys/<name>, so the run can be looked through afterwards like a storyboard.
  #
  # Once the browser is open, a journey leaves the database to it: records are set up before the first visit, and
  # anything from outside (a payment callback, say) arrives as a request. The test's own queries would share the
  # server's connection, and trip over it the way two requests at once do (see above).
  JOURNEYS_DIRECTORY = Rails.root.join("tmp/journeys")

  class_attribute :journey_name

  def self.journey(name)
    self.journey_name = name
    setup do
      @journey_steps = 0
      FileUtils.rm_rf journey_directory
      forget_the_shop_in_the_browser
    end
  end

  # The block is the step: what the person does, and what they should then see. The screenshot is taken once the
  # block's checks have passed, so it shows the screen the checks saw.
  def step(description)
    yield
    @journey_steps += 1
    page.save_screenshot journey_directory.join(format("%02d-%s.png", @journey_steps, description.parameterize))
  rescue Minitest::Assertion, Capybara::CapybaraError => error
    raise error.class, "At the step “#{description}”: #{error.message}\n#{browser_state}", error.backtrace
  end

  # Connects the shop to M-Pesa's simulator, as an owner would in Settings. Gives the secret part of the address
  # Safaricom calls back on.
  def connect_simulated_paybill(account = accounts(:acme))
    Account.without_isolation do
      Current.set(account: account) { account.mpesa_shortcodes.create!(name: "Paybill", shortcode: "174379", environment: "simulator").callback_token }
    end
  end

  # What Safaricom does once a customer has entered their PIN: posts the result to the shop's callback address. The
  # prompt's details come from the simulator's queued stand-in for that call, and the post goes through the server
  # like any other request, so nothing here reaches into the database while the browser is using it.
  def safaricom_confirms_payment(callback_token, receipt:)
    _shortcode, checkout_request_id, phone, amount = enqueued_jobs.reverse.find { _1[:job] == Mpesa::SimulatedCallbackJob }.fetch(:args)
    payload = Mpesa::SimulatedCallbackJob.payload(checkout_request_id, phone, amount)
    payload.dig("Body", "stkCallback", "CallbackMetadata", "Item").find { _1["Name"] == "MpesaReceiptNumber" }["Value"] = receipt

    response = Net::HTTP.post(URI("http://127.0.0.1:#{page.server.port}/webhooks/mpesa/#{callback_token}/stk"), payload.to_json, "Content-Type" => "application/json")
    assert_equal "200", response.code, "Safaricom's callback was refused"
  end

  private
    # Every journey starts in a browser that has never opened the shop. One browser serves the whole run, and a till
    # keeps things in it: its service worker, a copy of the catalogue (trusted for five minutes, and naming the till
    # it was taken on) and the sales it rang up offline.
    def forget_the_shop_in_the_browser(account = accounts(:acme))
      page.driver.browser.execute_cdp "Storage.clearDataForOrigin", origin: "http://#{account.subdomain}.localhost:#{page.server.port}", storageTypes: "all"
    end

    # Where the browser was when a step failed, what it last asked the server for, and anything it complained about.
    def browser_state
      requests = page.evaluate_script("performance.getEntriesByType('resource').slice(-6).map(entry => `${entry.name} (${Math.round(entry.duration)} ms)`)")
      console = page.driver.browser.logs.get(:browser).map(&:message)
      [ "Browser at #{page.current_url}", "Last requests: #{requests.join(", ")}", ("Console: #{console.join(" | ")}" if console.any?) ].compact.join("\n")
    rescue StandardError => error
      "(The browser's state couldn't be read: #{error.message})"
    end

    def journey_directory
      JOURNEYS_DIRECTORY.join(journey_name)
    end
end
