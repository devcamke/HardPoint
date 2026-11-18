require "application_system_test_case"

# The internet goes down mid-morning and the till keeps selling. The sale is kept on the computer, and when the
# connection is back it's sent and gets its receipt number. The connection is cut in the browser itself.
class OfflineTillJourneyTest < ApplicationSystemTestCase
  journey "offline-till"

  teardown { reconnect }

  test "the till sells with no connection and sends the sale when it's back" do
    step "Carl signs in and opens the Front counter till, where his shift is already open" do
      sign_in_with_browser users(:carl)
      click_on "Open a shift and start selling"
      click_on "Front counter"
      assert_text "50 bag here"
      assert_selector "[data-offline-sync-target=status]", text: "Online"
      wait_until_the_till_can_work_offline
    end

    step "The connection drops, and the till says so" do
      disconnect
      assert_selector "[data-offline-sync-target=status]", text: "Offline"
      assert_text "The till can't reach HardPoint."
    end

    step "He carries on at the offline till, which this computer kept a copy of" do
      click_on "Keep selling on the offline till"
      assert_text "Offline till Front counter · Main branch · Carl Cashier"
      assert_text "No offline sales on this till."
    end

    step "A bag of cement, from the prices the till last saw" do
      find("input[aria-label='Scan or search']").set "cement"
      click_on "Bamburi cement 50kg"
      within("aside") { assert_text "Total KES 800.00", normalize_ws: true }
      fill_in "Cash received", with: "1000"
      assert_text "Change KES 200.00"
    end

    step "The sale is kept on this till, waiting, under a number of its own" do
      click_on "Complete sale"
      assert_text(/Sale MAIN-OFF\S+ saved on this till · KES 800.00 · Change KES 200.00/)
      assert_selector "[data-offline-sync-target=status]", text: "Offline · 1 sale waiting"
    end

    step "The connection comes back, and the sale is sent and given its receipt number" do
      reconnect
      assert_text "You're back online and every offline sale has been sent."
      assert_selector "[data-offline-sync-target=status]", text: "Online"
      assert_text(/MAIN-000001 .* sent \(was MAIN-OFF\S+\)/, normalize_ws: true)
    end

    step "Back on the till, the bag has left the shelf" do
      click_on "Go back to the till"
      assert_text "49 bag here"
    end

    step "It's among the day's sales like any other" do
      click_link "Sales", exact: true
      assert_text "MAIN-000001"
      assert_text "Walk-in Carl Cashier KES 800.00", normalize_ws: true
    end
  end

  private
    def disconnect
      page.driver.browser.network_conditions = { offline: true, latency: 0, throughput: 0 }
    end

    def reconnect
      page.driver.browser.delete_network_conditions
    end

    # A till gets ready for this in the background each time it's opened online: its service worker takes over the
    # page and keeps the offline till and every script and stylesheet that page needs. A cashier never sees that
    # happen, so there's nothing on the screen to wait for.
    def wait_until_the_till_can_work_offline
      ready = page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1]
        const scripts = Object.values(JSON.parse(document.querySelector("script[type=importmap]").textContent).imports)
        const styles = [ ...document.querySelectorAll("link[rel=stylesheet]") ].map((link) => link.href)
        const needed = [ ...scripts, ...styles ].map((url) => new URL(url, location.href).pathname).filter((path) => path.startsWith("/assets/"))
        const started = Date.now()
        const check = async () => {
          const kept = new Set()
          for (const name of await caches.keys()) {
            for (const request of await (await caches.open(name)).keys()) kept.add(new URL(request.url).pathname)
          }
          const missing = needed.filter((path) => !kept.has(path))
          if (navigator.serviceWorker.controller && kept.has("/pos/offline") && missing.length === 0) return done("ready")
          if (Date.now() - started > 15000) return done(`not ready: controlled=${Boolean(navigator.serviceWorker.controller)}, offline page kept=${kept.has("/pos/offline")}, missing ${missing.slice(0, 5).join(", ")}`)
          setTimeout(check, 100)
        }
        check()
      JS
      assert_equal "ready", ready
    end
end
