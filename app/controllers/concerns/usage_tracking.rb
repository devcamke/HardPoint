# Counts the shortcuts people follow, from a from= tag on their links (see UsageCount and
# ApplicationHelper#tracked_path). Only GETs by signed-in staff count, and only names on UsageCount's list.
module UsageTracking
  extend ActiveSupport::Concern

  included do
    after_action :count_shortcut, if: -> { request.get? && params[:from].present? && authenticated? && (response.successful? || response.redirect?) }
  end

  private
    def count_shortcut
      UsageCount.record(params[:from])
    end
end
