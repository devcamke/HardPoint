require "test_helper"

class SafeCsvTest < ActiveSupport::TestCase
  test "typed text that a spreadsheet would run as a formula is written as text; numbers aren't touched" do
    csv = SafeCsv.generate { |rows| rows << [ "=HYPERLINK(\"http://x\")", "+254722", "@SUM(A1)", "-2+3", "Nails", "-150.00", 12, nil ] }
    assert_equal [ "'=HYPERLINK(\"http://x\")", "+254722", "'@SUM(A1)", "'-2+3", "Nails", "-150.00", "12", nil ], CSV.parse_line(csv)
  end

  test "importing takes the apostrophe off again" do
    assert_equal "=Cement", SafeCsv.unescape("'=Cement")
    assert_equal "'Quoted'", SafeCsv.unescape("'Quoted'")
  end
end
