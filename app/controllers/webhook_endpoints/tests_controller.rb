class WebhookEndpoints::TestsController < ApplicationController
  include DeveloperSettings

  def create
    endpoint = Current.account.webhook_endpoints.find(params[:webhook_endpoint_id])
    endpoint.send_test
    redirect_to endpoint, notice: "Test event sent; it appears below in a moment.", status: :see_other
  end
end
