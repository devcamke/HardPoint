module ToursHelper
  # What guided_tour_controller.js needs to run a tour.
  def guided_tour_data(tour)
    { id: tour.id, title: tour.title, page_pattern: tour.page_pattern, waiting: tour.waiting, steps: tour.steps,
      guide_url: help_article_url(tour.article, subdomain: false, anchor: "walkthrough-#{tour.id}") }.to_json
  end

  # A link that starts a tour. The tour is saved as the link is pressed, so it still starts if its screen is a step
  # or two away: the till asks which till this is first, and a stock take starts from the list of them.
  def link_to_tour(name = nil, tour, **options, &block)
    options[:data] = (options[:data] || {}).merge(guided_tour_start: guided_tour_data(tour))
    path = "#{tour.start}?tour=#{tour.id}"
    block ? link_to(path, **options, &block) : link_to(name, path, **options)
  end
end
