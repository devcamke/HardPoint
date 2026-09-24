module Pagination
  extend ActiveSupport::Concern

  PER_PAGE = 50

  included do
    helper_method :current_page
  end

  private
    def current_page
      [ params[:page].to_i, 1 ].max
    end

    # Fetches one extra row to know whether there's a next page without counting.
    def paginate(scope, per_page: PER_PAGE)
      records = scope.limit(per_page + 1).offset((current_page - 1) * per_page).to_a
      @next_page = current_page + 1 if records.size > per_page
      @previous_page = current_page - 1 if current_page > 1
      records.first(per_page)
    end
end
