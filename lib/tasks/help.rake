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

  # Retakes the screenshot behind each guided tour (config/help_tours.yml) and measures where its steps are, from
  # the running demo shop. See script/help_screenshots.mjs for what it needs.
  desc "Retake the guided tours' screenshots from the running demo shop"
  task screenshots: :environment do
    tours = HelpTour.all.map { { id: _1.id, page: _1.start, targets: _1.steps.map(&:target) } }
    input = Rails.root.join("tmp/help_tours.json").tap { _1.write(tours.to_json) }
    images = Rails.root.join("app/assets/images", HelpTour::IMAGES_DIRECTORY)

    system("node", Rails.root.join("script/help_screenshots.mjs").to_s, input.to_s, images.to_s, HelpTour::HOTSPOTS_PATH.to_s, exception: true)
    puts "Now run bin/rails help:export to update docs/USER_GUIDE.md"
  end
end
