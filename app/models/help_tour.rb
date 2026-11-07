# A guided tour of one screen, defined in config/help_tours.yml. In the shop it runs over the live screen; in the help
# centre its guide shows it as a walkthrough of a screenshot. Where each step sits on the screenshot is measured by
# `bin/rails help:screenshots` and kept in config/help_tour_hotspots.json.
class HelpTour < Data.define(:id, :title, :summary, :article, :page, :start, :waiting, :audience, :minutes, :steps, :image_size)
  DEFINITIONS_PATH = Rails.root.join("config/help_tours.yml")
  HOTSPOTS_PATH = Rails.root.join("config/help_tour_hotspots.json")
  IMAGES_DIRECTORY = "help/tours"
  AUDIENCES = %w[ everyone sellers stock purchasing customers reports ].freeze

  # One step. Its box is [ x, y, width, height ]: where its target is on the screenshot, as percentages of the image.
  # An optional step's target is only on some shops' screens (foreign notes, say).
  Step = Data.define(:target, :title, :text, :box, :optional) do
    def as_json(*) = { target:, title:, text: }
  end

  def self.all
    @all ||= begin
      hotspots = HOTSPOTS_PATH.exist? ? JSON.parse(HOTSPOTS_PATH.read) : {}
      YAML.load_file(DEFINITIONS_PATH).map do |id, tour|
        boxes = hotspots.dig(id, "steps") || {}
        steps = tour.fetch("steps").map do |step|
          Step.new(step.fetch("target"), step.fetch("title"), step.fetch("text"), boxes[step["target"]], step.fetch("optional", false))
        end
        new(id, tour.fetch("title"), tour.fetch("summary"), tour.fetch("article"), tour.fetch("page"), tour["start"] || tour.fetch("page"),
          tour["waiting"], tour.fetch("for"), tour.fetch("minutes"), steps, hotspots.dig(id, "size") || [ 1280, 800 ])
      end.freeze
    end
  end

  def self.find(id) = all.find { _1.id == id.to_s } or raise ActiveRecord::RecordNotFound, "No tour #{id}"
  def self.find_by(id:) = all.find { _1.id == id.to_s }
  def self.for_article(slug) = all.select { _1.article == slug }
  def self.available_to(membership) = all.select { _1.available_to?(membership) }

  def available_to?(membership)
    case audience
    when "everyone" then membership.present?
    when "sellers" then membership&.can_sell?
    when "stock" then membership&.can_manage_stock?
    when "purchasing" then membership&.can_purchase?
    when "customers" then membership&.can_sell? || membership&.can_manage_receivables?
    when "reports" then membership&.can_view_reports?
    else raise ArgumentError, "Unknown tour audience #{audience}"
    end
  end

  # The paths the tour runs on, as a pattern the browser understands too. :id is a record's number, so
  # /stock_counts/:id matches any stock take but not /stock_counts/new; :key is a name, as in /reports/:key.
  def page_pattern = "^#{Regexp.escape(page).gsub(":id", "[0-9]+").gsub(":key", "[a-z0-9_]+")}$"
  def runs_on?(path) = Regexp.new(page_pattern).match?(path)

  # The help centre's section for the tour's guide, so tours are grouped the same way.
  def section = HelpArticle.find(article).section

  def image = "#{IMAGES_DIRECTORY}/#{id}.png"

  # The steps that could be placed on the screenshot.
  def placed_steps = steps.select(&:box)

  def to_param = id
end
