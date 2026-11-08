# Platform staff setting a shop's add-ons and billing interval, e.g. after agreeing a yearly deal.
class Admin::Accounts::AddOnsController < Admin::BaseController
  include Admin::AccountScoped

  def update
    if @account.change_add_ons(**params.expect(account: %i[ extra_branches extra_registers billing_interval ]).to_h.symbolize_keys, by: nil)
      back_to_account notice: "#{@account.name} now pays #{helpers.money(@account.period_price_cents, currency: "KES")} #{@account.yearly? ? "a year" : "a month"} from its next invoice."
    else
      back_to_account alert: @account.errors.full_messages.to_sentence
    end
  end
end
