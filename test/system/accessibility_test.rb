require "application_system_test_case"

# Runs axe (https://github.com/dequelabs/axe-core) over the main screens, so a missing label, an unnamed button or
# text too faint to read fails the build. Checks WCAG 2.1 A and AA; serious and critical problems fail the test.
class AccessibilityTest < ApplicationSystemTestCase
  AXE = File.read(File.expand_path("support/axe.min.js", __dir__))

  def assert_accessible(screen)
    page.execute_script(AXE) unless page.evaluate_script("typeof window.axe !== 'undefined'")
    violations = page.evaluate_async_script(<<~'JS')
      const done = arguments[arguments.length - 1]
      axe.run(document, { runOnly: { type: "tag", values: [ "wcag2a", "wcag2aa", "wcag21a", "wcag21aa" ] } })
        .then(result => done(result.violations.filter(v => [ "serious", "critical" ].includes(v.impact))
          .map(v => `${v.id} (${v.impact}): ${v.help}\n    ${v.nodes.slice(0, 3).map(n => n.target.join(" ")).join("\n    ")}`)))
        .catch(error => done([ `axe failed: ${error}` ]))
    JS
    assert_empty violations, "#{screen}: #{violations.join("\n  ")}"
  end

  test "the public pages" do
    visit_public "/"
    assert_accessible "landing page"
    visit_shop accounts(:acme), "/session/new"
    assert_accessible "sign in"

    link = Account.without_isolation do
      Current.set(account: accounts(:acme)) do
        accounts(:acme).update!(features: accounts(:acme).features + [ "customer_portal" ])
        PortalLink.for(customers(:acme_contractor))
      end
    end
    visit_shop accounts(:acme), "/portal/#{link.token}"
    assert_accessible "customer portal"
  end

  test "the screens a shop uses every day" do
    sign_in_with_browser users(:amina)
    {
      "dashboard" => "/",
      "products" => "/products",
      "a product" => "/products/#{products(:acme_cement).id}",
      "customers" => "/customers",
      "a customer" => "/customers/#{customers(:acme_contractor).id}",
      "settings" => "/settings"
    }.each do |screen, path|
      visit path
      assert_accessible screen
    end
  end
end
