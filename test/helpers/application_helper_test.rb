require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "a status is a coloured dot before plain text, never a coloured capsule" do
    html = status_dot("Overdue", :danger)

    assert_dom_equal %(<span class="inline-flex items-center gap-1.5 whitespace-nowrap align-middle text-sm font-normal text-gray-800"><span class="size-2 shrink-0 rounded-full bg-red-600" aria-hidden="true"></span>Overdue</span>), html
    assert_no_match(/bg-red-50|rounded-full[^"]*px-/, html)
  end

  test "muted statuses are grey, and unknown tones are refused" do
    assert_match "text-gray-500", status_dot("Cancelled", :muted)
    assert_raises(KeyError) { status_dot("Odd", :purple) }
  end

  test "tracked paths keep their own query" do
    assert_equal "/reorder_list?branch_id=1&from=home%3Alow_stock", tracked_path("/reorder_list?branch_id=1", "home:low_stock")
  end
end
