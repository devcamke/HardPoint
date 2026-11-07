require "test_helper"

class HelpWalkthroughsTest < ActionDispatch::IntegrationTest
  setup { use_apex_domain }

  test "a guide shows its walkthrough: the screenshot, a numbered hotspot per step, and the steps written out" do
    tour = HelpTour.find("till")
    get help_article_path("selling")

    assert_select "figure#walkthrough-till[data-controller=walkthrough]" do
      assert_select "img[alt=?]", "Screenshot: #{tour.title}"
      assert_select ".walkthrough-hotspot", tour.steps.size
      assert_select ".walkthrough-hotspot[data-index='0'][style*='left:']", "1"
      assert_select "ol.walkthrough-steps li", tour.steps.size
      assert_select "ol.walkthrough-steps li:first-child strong", "#{tour.steps.first.title}."
    end
  end

  test "the help centre's front page leads to each walkthrough" do
    get help_path
    HelpTour.all.each do |tour|
      assert_select "a[href=?]", help_article_path(tour.article, anchor: "walkthrough-#{tour.id}")
    end
  end
end
