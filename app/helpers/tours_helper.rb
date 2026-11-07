module ToursHelper
  # What guided_tour_controller.js needs to run a tour.
  def guided_tour_data(tour)
    { id: tour.id, title: tour.title, page: tour.page, steps: tour.steps,
      guide_url: help_article_url(tour.article, subdomain: false, anchor: "walkthrough-#{tour.id}") }.to_json
  end

  # A link that starts a tour. The tour is saved as the link is pressed, so it still starts if its screen is a step
  # or two away (the till asks which till this is, or for a float, first).
  def link_to_tour(name = nil, tour, **options, &block)
    options[:data] = (options[:data] || {}).merge(guided_tour_start: guided_tour_data(tour))
    block ? link_to("#{tour.page}?tour=#{tour.id}", **options, &block) : link_to(name, "#{tour.page}?tour=#{tour.id}", **options)
  end
end
