# One search box for everything (Ctrl K, docs/SIMPLIFY.md change 7): products, customers, suppliers,
# documents by number, and pages by their name or the name they used to have. Answers in the popup
# from the top bar, or as a page of its own.
class SearchesController < ApplicationController
  LIMIT = 6

  def show
    @query = params[:q].to_s.squish.first(100)
    # A barcode or SKU scanned or typed in full goes straight to its product.
    scanned = Current.account.products.find_by_code(@query) unless turbo_frame_request?
    return redirect_to scanned if scanned

    @groups = @query.length >= 2 ? helpers.search_groups(@query, limit: LIMIT) : []

    render partial: "searches/results", locals: { query: @query, groups: @groups } if turbo_frame_request?
  end
end
