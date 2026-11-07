require "test_helper"

class HelpTourTest < ActiveSupport::TestCase
  test "every tour belongs to a guide, which shows it" do
    HelpTour.all.each do |tour|
      article = HelpArticle.find(tour.article)
      assert_includes HelpArticle::ARTICLES_PATH.join("_#{article.slug.underscore}.html.erb").read, %(HelpTour.find("#{tour.id}")),
        "The #{article.slug} guide should render the #{tour.id} walkthrough"
      assert_includes HelpTour::AUDIENCES, tour.audience
    end
  end

  test "every step is on its screenshot (run bin/rails help:screenshots after changing a tour or its screen)" do
    HelpTour.all.each do |tour|
      assert Rails.root.join("app/assets/images", tour.image).exist?, "#{tour.image} is missing"
      tour.steps.each do |step|
        next if step.optional && step.box.nil? # shown to some people only, like the approval PIN to cashiers
        assert step.box, "#{tour.id}: #{step.target} isn't placed on the screenshot"
        x, y, width, height = step.box
        assert [ x, y, width, height ].all? { _1.between?(0, 100) } && x + width <= 100.1 && y + height <= 100.1,
          "#{tour.id}: #{step.target} is off the screenshot"
      end
    end
  end

  test "a step only some shops have is marked optional" do
    assert HelpTour.find("till").steps.none?(&:optional)
    assert HelpTour.find("close-shift").steps.find { _1.target == "close-foreign" }.optional
  end

  test "the steps a guide's walkthroughs show can be searched for" do
    assert_includes HelpArticle.search("park this sale"), HelpArticle.find("selling")
  end

  test "who each tour is for" do
    accountant = memberships(:carl_acme).dup.tap { _1.role = "accountant" }

    assert HelpTour.find("till").available_to?(memberships(:carl_acme))
    assert_not HelpTour.find("till").available_to?(accountant)
    assert HelpTour.find("home").available_to?(accountant)
    assert_not HelpTour.find("home").available_to?(nil)
    assert_not HelpTour.find("stock-take").available_to?(memberships(:carl_acme))
    assert HelpTour.find("receiving").available_to?(memberships(:sara_acme))
    assert HelpTour.find("mpesa").available_to?(memberships(:amina_acme))
    assert_not HelpTour.find("staff").available_to?(memberships(:sara_acme))
    assert HelpTour.find("settings").available_to?(memberships(:sara_acme))
  end

  test "a tour can run on any record's page, and start somewhere else" do
    tour = HelpTour.find("stock-take")
    assert tour.runs_on?("/stock_counts/42")
    assert_not tour.runs_on?("/stock_counts")
    assert_not tour.runs_on?("/stock_counts/42/lines")
    assert_not tour.runs_on?("/stock_counts/new")
    assert_not HelpTour.find("customer").runs_on?("/customers/new")
    assert_equal "/stock_counts", tour.start
    assert_equal "/", HelpTour.find("home").start
    assert HelpTour.find("receiving").runs_on?("/goods_receipts/new")
  end
end
