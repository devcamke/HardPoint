# The control panel at the top of a list page, laid out the way Odoo does it: the "New" button and the
# title on the left, a search bar in the middle that shows the active filters as removable facets with a
# dropdown of filters, and the pager on the right.
module ControlPanelHelper
  # One group of filters in the search dropdown.
  #   param:   the query parameter it sets
  #   label:   the group's heading, and the facet's prefix ("Status: Open")
  #   options: [ [ value, label ], … ]
  #   value:   the value in force now
  #   clear:   the value that means "no filter" (nil removes the parameter)
  #   facet:   false for settings that are always in force, such as the branch whose stock is shown
  #   type:    :date for a date picker instead of options
  #   section: :filters, or :group_by for Odoo's "Group By" column
  #   drops:   parameters a date picker clears when it's used, e.g. the preset period it replaces
  SearchFilter = Data.define(:param, :label, :options, :value, :clear, :facet, :type, :section, :drops) do
    def initialize(param:, label: nil, options: [], value: nil, clear: nil, facet: true, type: :options, section: :filters, drops: [])
      super(param: param.to_s, label:, options: options.map { |v, l| [ v.to_s, l ] }, value: value&.to_s, clear: clear&.to_s, facet:, type:,
        section:, drops: drops.map(&:to_s))
    end

    def active?(option_value) = value == option_value
    def option_label(option_value) = options.to_h[option_value]

    def facet_text
      return unless facet && value.present? && value != clear

      text = type == :date ? I18n.l(Date.parse(value), format: :long) : option_label(value)
      return unless text

      label ? "#{label}: #{text}" : text
    rescue Date::Error
      nil
    end
  end

  def search_filter(param, **options) = SearchFilter.new(param:, **options)

  # The current list URL with some parameters changed (nil removes one). Always goes back to page 1.
  def search_url(changes = {})
    query = request.query_parameters.except("page").merge(changes.transform_keys(&:to_s)).compact
    query.empty? ? request.path : "#{request.path}?#{query.to_query}"
  end

  def search_facets(filters, query_param:)
    facets = filters.filter_map do |filter|
      text = filter.facet_text
      [ text, search_url(filter.param => filter.clear) ] if text
    end
    if query_param && (query = request.query_parameters[query_param.to_s]).present?
      facets << [ "Search: #{query}", search_url(query_param => nil) ]
    end
    facets
  end

  # Odoo's pager: "51-100" between previous and next arrows.
  def pager_range(records)
    return if records.nil? || (@previous_page.nil? && @next_page.nil?)

    first = (current_page - 1) * Pagination::PER_PAGE + 1
    "#{first}-#{first + records.size - 1}"
  end
end
