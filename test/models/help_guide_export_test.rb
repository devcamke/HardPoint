require "test_helper"

class HelpGuideExportTest < ActiveSupport::TestCase
  setup { @markdown = HelpGuideExport.new.to_markdown }

  test "every guide is in the user guide, and every link inside it has somewhere to go" do
    HelpArticle.all.each { assert_includes @markdown, %(<a id="#{_1.slug}"></a>\n\n### #{_1.title}) }

    anchors = @markdown.scan(/<a id="([\w-]+)"><\/a>/).flatten
    links = @markdown.scan(/\]\(#([\w-]+)\)/).flatten.uniq
    assert_empty links - anchors
    assert_no_match(/<\/?(p|li|ul|ol|strong|code)\b/, @markdown, "HTML left over")
  end

  test "docs/USER_GUIDE.md is up to date (run bin/rails help:export)" do
    assert_equal @markdown, Rails.root.join("docs/USER_GUIDE.md").read
  end
end
