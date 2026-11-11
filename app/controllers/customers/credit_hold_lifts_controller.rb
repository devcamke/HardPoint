# An owner or manager lifting a customer's credit hold for a while, with a reason, or putting it back.
class Customers::CreditHoldLiftsController < ApplicationController
  before_action { head :forbidden unless current_membership&.approver? }
  before_action { @customer = Current.account.customers.find(params[:customer_id]) }

  def create
    if @customer.lift_credit_hold(by: Current.user, days: params[:days], reason: params[:reason])
      redirect_to @customer, notice: "Hold lifted until #{l(@customer.credit_hold_lifted_until, format: :long)}.", status: :see_other
    else
      redirect_to @customer, alert: @customer.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    @customer.restore_credit_hold(by: Current.user)
    redirect_to @customer, notice: "#{@customer.name} is held again while invoices are too long overdue.", status: :see_other
  end
end
