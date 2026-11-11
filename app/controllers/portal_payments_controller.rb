# "Pay with M-Pesa" on the customer portal: a prompt to the customer's phone for what they choose to pay on account,
# then a page that waits for their PIN. What's paid is recorded on the account by the callback (Mpesa::StkRequest).
class PortalPaymentsController < ApplicationController
  include PortalAccess

  # A prompt lands on someone's phone: a link can't be used to keep pushing them at a number.
  rate_limit to: 5, within: 10.minutes, only: :create, by: -> { params[:token].to_s },
    with: -> { redirect_to portal_path(params[:token]), alert: "Too many payment prompts. Wait a few minutes and try again.", status: :see_other }

  def create
    shortcode = Current.account.portal_shortcode
    phone = PhoneNumber.normalize(params[:phone])
    amount_cents = Monetary.to_cents(params[:amount])

    alert =
      if shortcode.nil? then "#{Current.account.name} doesn't take M-Pesa here yet."
      elsif phone.nil? then "Enter a Safaricom number like 0722 000 111."
      elsif amount_cents.to_i < 100 then "Enter an amount of at least #{helpers.money(100)}."
      elsif @customer.stk_requests.pending.where(created_at: Mpesa::StkRequest::EXPIRES_AFTER.ago..).exists?
        "A prompt is already waiting on a phone. Enter the PIN there, or wait a few minutes and try again."
      end
    return redirect_to(portal_path(@link.token), alert: alert, status: :see_other) if alert

    stk_request = shortcode.request_account_payment(customer: @customer, phone: phone, amount_cents: amount_cents, portal_link: @link)
    if stk_request.failed?
      redirect_to portal_path(@link.token), alert: "The prompt couldn't be sent: #{stk_request.result_description}", status: :see_other
    else
      redirect_to portal_payment_path(@link.token, stk_request), status: :see_other
    end
  end

  # Shown while the customer enters their PIN; refreshes itself, and chases Safaricom when the callback is late.
  def show
    @stk_request = @customer.stk_requests.where(portal_link: @link).find(params[:id])
    if @stk_request.pending? && @stk_request.created_at < Mpesa::StkRequest::STATUS_CHECK_AFTER.ago && @stk_request.updated_at < 10.seconds.ago
      @stk_request.touch # at most one check with Safaricom every 10 seconds
      Mpesa::StatusCheckJob.perform_later(@stk_request)
    end
  end
end
