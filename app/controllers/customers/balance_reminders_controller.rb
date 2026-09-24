# A text telling a customer what they owe and how to pay it.
class Customers::BalanceRemindersController < ApplicationController
  before_action :ensure_can_manage_receivables
  rate_limit to: 30, within: 10.minutes, only: :create

  def create
    customer = Current.account.customers.find(params[:customer_id])
    text = Sms::Message.balance_reminder(customer)

    if text.persisted?
      redirect_to customer, notice: "Reminder texted to #{PhoneNumber.display(text.recipient)}.", status: :see_other
    else
      redirect_to customer, alert: text.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
