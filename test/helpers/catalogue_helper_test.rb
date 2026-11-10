require "test_helper"

class CatalogueHelperTest < ActionView::TestCase
  test "money reads amounts kept as text, as some old Activity entries have them" do
    assert_equal "KES 21,732.50", money("2173250.0", currency: "KES")
    assert_equal "KES 21,732.50", money(2173250, currency: "KES")
    assert_equal "—", money(nil)
  end
end
