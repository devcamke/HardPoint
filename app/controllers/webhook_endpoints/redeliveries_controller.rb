class WebhookEndpoints::RedeliveriesController < ApplicationController
  include DeveloperSettings

  def create
    endpoint = Current.account.webhook_endpoints.find(params[:webhook_endpoint_id])
    endpoint.deliveries.find(params[:delivery_id]).redeliver
    redirect_to endpoint, notice: "Sending it again.", status: :see_other
  end
end
