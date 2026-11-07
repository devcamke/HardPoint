# Settings › Features: switch on only what the shop uses (Account::Features).
class FeaturesController < ApplicationController
  before_action :ensure_can_manage_account

  def show
  end

  def update
    Current.account.assign_attributes(features: params.dig(:account, :features).to_a, features_reviewed_at: Time.current)

    if Current.account.save
      redirect_to features_path, notice: "Features saved.", status: :see_other
    else
      render :show, status: :unprocessable_entity
    end
  end
end
