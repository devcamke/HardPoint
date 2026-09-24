class ApiKeysController < ApplicationController
  include DeveloperSettings

  def new
    @api_key = Current.account.api_keys.new(scope: "read")
  end

  # The token is shown on this page once; only its digest is kept.
  def create
    @api_key = Current.account.api_keys.new(params.expect(api_key: %i[ name scope ]))
    if @api_key.save
      render :created, status: :created
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    api_key = Current.account.api_keys.active.find(params[:id])
    api_key.revoke
    redirect_to developers_path, notice: "“#{api_key.name}” revoked; requests with it are refused from now on.", status: :see_other
  end
end
