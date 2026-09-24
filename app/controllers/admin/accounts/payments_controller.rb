# Recording a payment that reached HardPoint another way, such as a bank transfer.
class Admin::Accounts::PaymentsController < Admin::BaseController
  include Admin::AccountScoped

  def create
    if @account.record_manual_payment(params[:reference].to_s.strip.first(100))
      back_to_account notice: "Payment recorded; the invoice is paid and the owner has a receipt."
    else
      back_to_account alert: "Nothing is due."
    end
  end
end
