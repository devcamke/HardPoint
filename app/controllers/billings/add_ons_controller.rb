# Extra branches and tills on top of the plan, and monthly or yearly billing.
class Billings::AddOnsController < ApplicationController
  include BillingScoped

  def update
    account = Current.account
    if account.change_add_ons(**add_on_params)
      redirect_to billing_path, notice: "Saved. Your next invoice will be #{helpers.money(account.period_price_cents, currency: "KES")} for #{account.yearly? ? "a year" : "a month"}.", status: :see_other
    else
      redirect_to billing_path, alert: account.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def add_on_params
      params.expect(account: %i[ extra_branches extra_registers billing_interval ]).to_h.symbolize_keys
    end
end
