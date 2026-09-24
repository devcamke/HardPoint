# Paystack sends the owner back here after checkout; the payment is checked with Paystack (the
# webhook does the same, whichever arrives first).
class Billings::CardReturnsController < ApplicationController
  include BillingScoped

  def show
    payment = Current.account.billing_payments.find_by!(provider: "paystack", reference: params[:reference].to_s)
    status, amount, currency = Billing::Paystack.new.verify(payment.reference)

    if status == "success" && currency == payment.invoice.currency
      payment.succeed(receipt: payment.reference, amount_cents: amount)
      redirect_to billing_path, notice: "Paid, thank you."
    else
      payment.fail("Paystack says #{status || "no payment"}")
      redirect_to billing_path, alert: "The card payment didn't go through."
    end
  rescue Billing::Paystack::Refused, JsonHttp::Unreachable
    redirect_to billing_path, notice: "We're confirming the payment with Paystack; this page will show it shortly."
  end
end
