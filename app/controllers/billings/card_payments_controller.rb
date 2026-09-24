# Paying HardPoint by card: off to Paystack's checkout (or the simulated one in development).
class Billings::CardPaymentsController < ApplicationController
  include BillingScoped

  def create
    invoice = open_invoice or return
    payment = invoice.payments.create!(account: Current.account, provider: "paystack", amount_cents: invoice.amount_cents,
      reference: "HP-#{invoice.id}-#{SecureRandom.hex(6)}")

    if Billing::Paystack.simulated?
      redirect_to billing_card_simulator_path(reference: payment.reference), status: :see_other
    else
      url = Billing::Paystack.new.checkout_url(payment, email: Current.user.email_address, callback_url: billing_card_return_url)
      redirect_to url, allow_other_host: true, status: :see_other
    end
  rescue Billing::Paystack::Refused, JsonHttp::Unreachable => error
    payment&.fail(error.message)
    redirect_to billing_path, alert: "Card payment couldn't start: #{error.message}", status: :see_other
  end
end
