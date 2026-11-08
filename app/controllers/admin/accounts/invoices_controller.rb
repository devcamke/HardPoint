# Billing a shop for something outside its subscription: setting it up on site, training, a
# hardware kit. The owner gets the invoice by email and pays it from the Billing page like any other.
class Admin::Accounts::InvoicesController < Admin::BaseController
  include Admin::AccountScoped

  def create
    amount_cents = (params[:amount].to_s.delete(",").to_d * 100).round
    if amount_cents <= 0
      back_to_account alert: "The amount must be more than zero."
      return
    end

    invoice = @account.issue_one_off_invoice(params[:description].to_s.strip.first(200), amount_cents, due_in: params[:due_in].to_i.clamp(1, 90).days)
    back_to_account notice: "Invoice #{invoice.number} for #{helpers.money(invoice.amount_cents, currency: "KES")} sent to #{@account.name}'s owners."
  rescue ActiveRecord::RecordInvalid => error
    back_to_account alert: error.record.errors.full_messages.to_sentence
  end
end
