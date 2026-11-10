class WebhookEndpoints::EnablementsController < ApplicationController
  include DeveloperSettings

  def create
    endpoint = Current.account.webhook_endpoints.find(params[:webhook_endpoint_id])
    endpoint.enable
    redirect_to endpoint, notice: "Endpoint switched back on. Events skipped while it was off are being sent; resend any failed ones below.", status: :see_other
  end
end
