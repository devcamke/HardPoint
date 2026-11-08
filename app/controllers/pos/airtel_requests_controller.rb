# Prompts sent to a customer's phone to pay with Airtel Money, and the till checking on them.
class Pos::AirtelRequestsController < ApplicationController
  include PosSale
  # A prompt lands on a customer's phone; a till can't be used to keep pushing them at someone.
  rate_limit to: 10, within: 1.minute, only: :create, by: -> { cookies.signed[:session_id] || request.remote_ip },
    with: -> { render plain: "Too many payment prompts from this till; wait a minute and try again.", status: :too_many_requests }

  def create
    merchant = Airtel::Merchant.for_branch(@sale.branch)
    phone = PhoneNumber.normalize(params[:phone])
    return render_cart(alert: "Airtel Money isn't set up for this branch", status: :unprocessable_entity) unless merchant
    return render_cart(alert: "Enter an Airtel number like 0733 000 111", status: :unprocessable_entity) unless phone
    return render_cart(alert: "Nothing is due on this sale", status: :unprocessable_entity) unless @sale.balance_due_cents.positive?

    request = merchant.request_payment(sale: @sale, phone: phone, amount_cents: @sale.balance_due_cents)
    if request.failed?
      render_cart alert: "Airtel Money prompt not sent: #{request.result_description}", status: :unprocessable_entity
    else
      render_cart message: "Prompt sent to #{PhoneNumber.display(phone)}. Ask them to enter their Airtel Money PIN."
    end
  rescue ActiveRecord::RecordInvalid => invalid
    render_cart alert: invalid.record.errors.full_messages.to_sentence, status: :unprocessable_entity
  end

  # Polled by the till while the customer answers. Callbacks get lost, so the till asks Airtel too.
  def show
    request = @sale.airtel_requests.find(params[:id])
    if request.pending? && request.created_at < Airtel::Request::STATUS_CHECK_AFTER.ago && request.updated_at < 10.seconds.ago
      request.touch # at most one check with Airtel every 10 seconds
      Airtel::StatusCheckJob.perform_later(request)
    end

    unless request.pending?
      if request.paid?
        flash[:notice] = "Airtel Money #{request.airtel_money_id} received from #{PhoneNumber.display(request.phone)}."
      else
        flash[:alert] = "Airtel Money not paid: #{request.result_description.presence || request.status.humanize}."
      end
    end
    render json: { status: request.status, location: @sale.reload.completed? ? pos_path(completed: @sale.id) : pos_path }
  end

  def destroy
    @sale.airtel_requests.find(params[:id]).cancel
    redirect_to pos_path, notice: "Stopped waiting. If they pay anyway, the payment will show under Airtel Money to use.", status: :see_other
  end

  private
    # The sale being polled may have just completed, so it's found among this shift's sales.
    def set_sale
      @sale = action_name == "show" ? current_shift.sales.find(Current.account.airtel_requests.find(params[:id]).sale_id) : super
    end
end
