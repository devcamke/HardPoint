# Reorder suggestions were merged into Stock › Reorder; old links and bookmarks land there.
class ReorderSuggestionsController < ApplicationController
  def show
    redirect_to reorder_list_path(request.query_parameters), status: :moved_permanently
  end
end
