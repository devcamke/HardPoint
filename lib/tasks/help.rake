# The in-app help guides as one Markdown document (docs/USER_GUIDE.md), so the whole manual can be read, printed or
# shared outside the app. The guides in app/views/help/articles stay the source: run `bin/rails help:export` after
# changing one.
namespace :help do
  desc "Write every help guide into docs/USER_GUIDE.md"
  task export: :environment do
    path = Rails.root.join("docs/USER_GUIDE.md")
    File.write(path, HelpGuideExport.new.to_markdown)
    puts "Wrote #{HelpArticle.all.size} guides to #{path.relative_path_from(Rails.root)}"
  end
end
