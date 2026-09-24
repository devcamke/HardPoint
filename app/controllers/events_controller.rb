class EventsController < ApplicationController
  PAGE_SIZE = 50

  before_action :ensure_can_manage_staff

  def index
    @events = Current.account.account_events.chronologically.includes(:creator)
      .before(Current.account.account_events.find_by(id: params[:before])).limit(PAGE_SIZE)
  end
end
