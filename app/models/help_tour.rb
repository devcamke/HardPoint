# A guided tour of one screen, defined in config/help_tours.yml. In the shop it runs over the live screen; in the help
# centre its guide shows it as a walkthrough of a screenshot. Where each step sits on the screenshot is measured by
# `bin/rails help:screenshots` and kept in config/help_tour_hotspots.json.
class HelpTour < Data.define(:id, :title, :summary, :article, :page, :audience, :minutes, :steps, :image_size)
  DEFINITIONS_PATH = Rails.root.join("config/help_tours.yml")
  HOTSPOTS_PATH = Rails.root.join("config/help_tour_hotspots.json")
  IMAGES_DIRECTORY = "help/tours"
  AUDIENCES = %w[ everyone sellers ].freeze

  # One step. Its box is [ x, y, width, height ]: where its target is on the screenshot, as percentages of the image.
  Step = Data.define(:target, :title, :text, :box) do
    def as_json(*) = { target:, title:, text: }
  end

  def self.all
    @all ||= begin
      hotspots = HOTSPOTS_PATH.exist? ? JSON.parse(HOTSPOTS_PATH.read) : {}
      YAML.load_file(DEFINITIONS_PATH).map do |id, tour|
        boxes = hotspots.dig(id, "steps") || {}
        steps = tour.fetch("steps").map { |step| Step.new(step.fetch("target"), step.fetch("title"), step.fetch("text"), boxes[step["target"]]) }
        new(id, tour.fetch("title"), tour.fetch("summary"), tour.fetch("article"), tour.fetch("page"), tour.fetch("for"), tour.fetch("minutes"),
          steps, hotspots.dig(id, "size") || [ 1280, 800 ])
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
    else raise ArgumentError, "Unknown tour audience #{audience}"
    end
  end

  def image = "#{IMAGES_DIRECTORY}/#{id}.png"

  # The steps that could be placed on the screenshot.
  def placed_steps = steps.select(&:box)

  def to_param = id
end
