# Paying HardPoint by M-Pesa: a prompt to the owner's phone, and the page checking on it.
class Billings::MpesaPaymentsController < ApplicationController
  include BillingScoped

  def create
    invoice = open_invoice or return
    phone = PhoneNumber.normalize(params[:phone])
    return redirect_to(billing_path, alert: "Enter a Safaricom number like 0722 000 111.", status: :see_other) unless phone

    payment = Billing::MpesaShortcode.new.request_payment(invoice: invoice, phone: phone)
    if payment.failed?
      redirect_to billing_path, alert: "M-Pesa prompt not sent: #{payment.failure}", status: :see_other
    else
      redirect_to billing_path, notice: "Check #{PhoneNumber.display(phone)} and enter your M-Pesa PIN to pay #{Money.format(invoice.amount_cents)}.", status: :see_other
    end
  end

  # Polled while the prompt is open.
  def show
    payment = Current.account.billing_payments.find(params[:id])
    unless payment.pending?
      flash[:notice] = "Paid, thank you. #{payment.receipt}" if payment.succeeded?
      flash[:alert] = "M-Pesa payment didn't go through: #{payment.failure}" if payment.failed?
    end
    render json: { status: payment.status, location: billing_path }
  end
end
