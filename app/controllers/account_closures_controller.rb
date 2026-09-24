class AccountClosuresController < ApplicationController
  include OwnerOnly
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to account_data_path, alert: "Try again later." }

  def create
    if params[:confirmation].to_s.strip.downcase != Current.account.subdomain
      redirect_to account_data_path, alert: "Type #{Current.account.subdomain} to confirm.", status: :see_other
    elsif Current.account.request_closure(by: Current.user, password: params[:password])
      redirect_to account_data_path, notice: "#{Current.account.name} will be deleted on #{I18n.l(Current.account.deletion_scheduled_for.to_date, format: :long)}. You can cancel until then.", status: :see_other
    else
      redirect_to account_data_path, alert: Current.account.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    Current.account.cancel_closure(by: Current.user)
    redirect_to account_data_path, notice: "Closure cancelled. #{Current.account.name} is open again.", status: :see_other
  end
end
