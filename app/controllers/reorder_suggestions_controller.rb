class ReorderSuggestionsController < ApplicationController
  before_action :ensure_can_purchase

  def show
    @suggestion = ReorderSuggestion.new(Current.account, selected_branch)
  end
end
