class DevelopersController < ApplicationController
  include DeveloperSettings

  def show
    @api_keys = Current.account.api_keys.active.chronologically.includes(:creator)
    @endpoints = Current.account.webhook_endpoints.alphabetically
    @last_deliveries = Current.account.webhook_deliveries.where(id: WebhookDelivery.select("max(id)").group(:endpoint_id)).index_by(&:endpoint_id)
  end
end
