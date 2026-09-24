class WebhookEndpoints::SecretsController < ApplicationController
  include DeveloperSettings

  def create
    endpoint = Current.account.webhook_endpoints.find(params[:webhook_endpoint_id])
    endpoint.roll_secret
    redirect_to endpoint, notice: "New signing secret made. Events are signed with it from now on; update your receiver.", status: :see_other
  end
end
