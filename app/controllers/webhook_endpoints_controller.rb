class WebhookEndpointsController < ApplicationController
  include DeveloperSettings
  before_action :set_endpoint, only: %i[ show edit update destroy ]

  def show
    @deliveries = @endpoint.deliveries.chronologically.limit(30)
  end

  def new
    @endpoint = Current.account.webhook_endpoints.new(event_types: %w[ sale.completed ])
  end

  def create
    @endpoint = Current.account.webhook_endpoints.new(endpoint_params)
    if @endpoint.save
      redirect_to @endpoint, notice: "Endpoint added. Copy its signing secret below into your receiver.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @endpoint.update(endpoint_params)
      redirect_to @endpoint, notice: "Endpoint saved.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @endpoint.destroy!
    redirect_to developers_path, notice: "Endpoint removed.", status: :see_other
  end

  private
    def set_endpoint
      @endpoint = Current.account.webhook_endpoints.find(params[:id])
    end

    def endpoint_params
      params.expect(webhook_endpoint: [ :url, :description, event_types: [] ])
    end
end
