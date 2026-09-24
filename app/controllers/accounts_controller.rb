class AccountsController < ApplicationController
  before_action :ensure_can_manage_account

  def edit
    @account = Current.account
  end

  def update
    @account = Current.account

    if @account.update(account_params)
      redirect_to edit_account_path, notice: "Shop settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def account_params
      params.expect(account: %i[ name time_zone currency require_two_factor_for_managers max_cashier_discount_percent receipt_footer ])
    end
end
