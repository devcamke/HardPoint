# A stand-in for Paystack's checkout in development and demos (no Paystack key configured).
class Billings::CardSimulatorsController < ApplicationController
  include BillingScoped
  before_action { head :not_found unless Billing::Paystack.simulated? && Billing::Paystack.available? }
  before_action :set_payment

  def show
  end

  def create
    if params[:outcome] == "decline"
      @payment.fail("Card declined (simulated)")
      redirect_to billing_path, alert: "The card was declined.", status: :see_other
    else
      @payment.succeed(receipt: "SIM-#{@payment.reference.last(6).upcase}")
      redirect_to billing_path, notice: "Paid, thank you.", status: :see_other
    end
  end

  private
    def set_payment
      @payment = Current.account.billing_payments.pending.find_by!(provider: "paystack", reference: params[:reference].to_s)
    end
end
