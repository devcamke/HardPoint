# Prompts sent to a customer's phone to pay with M-Pesa (STK push), and the till checking on them.
class Pos::MpesaRequestsController < ApplicationController
  include PosSale

  def create
    shortcode = Mpesa::Shortcode.for_branch(@sale.branch)
    phone = PhoneNumber.normalize(params[:phone])
    return render_cart(alert: "M-Pesa isn't set up for this branch", status: :unprocessable_entity) unless shortcode
    return render_cart(alert: "Enter a Safaricom number like 0722 000 111", status: :unprocessable_entity) unless phone
    return render_cart(alert: "Nothing is due on this sale", status: :unprocessable_entity) unless @sale.balance_due_cents.positive?

    stk_request = shortcode.request_payment(sale: @sale, phone: phone, amount_cents: @sale.balance_due_cents)
    if stk_request.failed?
      render_cart alert: "M-Pesa prompt not sent: #{stk_request.result_description}", status: :unprocessable_entity
    else
      render_cart message: "Prompt sent to #{PhoneNumber.display(phone)}. Ask them to enter their M-Pesa PIN."
    end
  rescue ActiveRecord::RecordInvalid => invalid
    render_cart alert: invalid.record.errors.full_messages.to_sentence, status: :unprocessable_entity
  end

  # Polled by the till while the customer answers. Late callbacks are chased with a status check.
  def show
    stk_request = @sale.stk_requests.find(params[:id])
    if stk_request.pending? && stk_request.created_at < Mpesa::StkRequest::STATUS_CHECK_AFTER.ago && stk_request.updated_at < 10.seconds.ago
      stk_request.touch # at most one check with Safaricom every 10 seconds
      Mpesa::StatusCheckJob.perform_later(stk_request)
    end

    unless stk_request.pending?
      if stk_request.paid?
        flash[:notice] = "M-Pesa #{stk_request.receipt_number} received from #{PhoneNumber.display(stk_request.phone)}."
      else
        flash[:alert] = "M-Pesa not paid: #{stk_request.result_description.presence || stk_request.status.humanize}."
      end
    end
    render json: { status: stk_request.status, location: @sale.reload.completed? ? pos_path(completed: @sale.id) : pos_path }
  end

  def destroy
    @sale.stk_requests.find(params[:id]).cancel
    redirect_to pos_path, notice: "Stopped waiting. If they pay anyway, the payment will show under M-Pesa to use.", status: :see_other
  end

  private
    # The sale being polled may have just completed, so it's found among this shift's sales.
    def set_sale
      @sale = action_name == "show" ? current_shift.sales.find(Current.account.mpesa_stk_requests.find(params[:id]).sale_id) : super
    end
end
