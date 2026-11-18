require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # Shops live on subdomains (acme.localhost); Chrome sends every *.localhost to this machine.
  Capybara.server_host = "127.0.0.1"
  Capybara.always_include_port = true

  # One request at a time. A test's browser and server share a single database connection, and which shop that
  # connection may see is a setting on the connection (Account::Isolation). Two requests at once (Turbo prefetches a
  # link the mouse happens to rest on) can clear it under each other: the second then finds no session and is sent
  # to sign in. Each request has a connection of its own outside tests.
  Capybara.server = :puma, { Threads: "1:1" }

  # With one request at a time, a click can wait its turn behind a page Turbo is prefetching, and the first time a
  # page is asked for it is slow to build. Two seconds, Capybara's usual patience, isn't enough for both.
  Capybara.default_max_wait_time = 10

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

  private
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
