# A text telling a customer how many points they have, what they're worth and when any run out.
class Customers::PointsTextsController < ApplicationController
  rate_limit to: 30, within: 10.minutes, only: :create

  def create
    customer = Current.account.customers.find(params[:customer_id])
    text = Sms::Message.points_balance(customer) if Current.account.loyalty_program

    if text&.persisted?
      redirect_to customer_path(customer, anchor: "loyalty_points"), notice: "Points balance texted to #{PhoneNumber.display(text.recipient)}.", status: :see_other
    else
      redirect_to customer_path(customer, anchor: "loyalty_points"), alert: text ? text.errors.full_messages.to_sentence : "This shop has no loyalty points.", status: :see_other
    end
  end
end
