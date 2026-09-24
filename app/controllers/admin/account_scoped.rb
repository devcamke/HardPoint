# Platform actions on one shop run as that shop (not across all of them), so its events, invoices and
# emails are its own. Every action is recorded in the shop's activity with the administrator's email.
module Admin::AccountScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_account
    around_action :within_account
  end

  private
    def set_account
      @account = Account.find(params[:account_id])
    end

    def within_account(&)
      Current.set(account: @account, &)
    end

    def back_to_account(**flash)
      redirect_to admin_account_path(@account), status: :see_other, **flash
    end
end
