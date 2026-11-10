require "test_helper"

class ThemeTest < ActiveSupport::TestCase
  test "every preset can carry white writing, and its shades run from nearly white to nearly black" do
    Theme::PRESETS.each_value do |preset|
      assert Theme.readable?(preset.color), "#{preset.name} is too light for white text"
      shades = Theme.new(preset.color).shades
      assert_equal [ 50, 100, 200, 300, 400, 500, 600, 700, 800, 900 ], shades.keys
      assert_equal preset.color, shades[500]
      luminances = shades.values.map { Theme.relative_luminance(_1) }
      assert_equal luminances.sort.reverse, luminances, "#{preset.name}'s shades get darker in order"
      assert_operator luminances.first, :>, 0.85
    end
  end

  test "the default theme adds nothing; another overrides the primary and link colours" do
    assert_equal "", Theme.new(nil).css
    css = Theme.new("#1D4ED8").css
    assert_match "--color-primary-500: #1D4ED8;", css
    assert_match "--color-accent-600:", css
  end

  test "colours are tidied, and light ones aren't readable" do
    assert_equal "#1D4ED8", Theme.normalize(" 1d4ed8 ")
    assert_nil Theme.normalize("blue")
    assert_not Theme.readable?("#FDE68A")
    assert Theme.readable?("#000000")
  end
end
