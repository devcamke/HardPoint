class WebhookEndpoints::EnablementsController < ApplicationController
  include DeveloperSettings

  def create
    endpoint = Current.account.webhook_endpoints.find(params[:webhook_endpoint_id])
    endpoint.enable
    redirect_to endpoint, notice: "Endpoint switched back on. Resend any failed events below.", status: :see_other
  end
end
