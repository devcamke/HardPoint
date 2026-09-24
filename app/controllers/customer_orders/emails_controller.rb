# Emails the quote or order to the customer as a PDF.
class CustomerOrders::EmailsController < ApplicationController
  include CustomerOrderScoped

  def create
    email = params[:email].presence || @customer_order.customer.email

    if email.to_s.match?(URI::MailTo::EMAIL_REGEXP)
      CustomerOrdersMailer.with(customer_order: @customer_order, email: email, sender: Current.user).document.deliver_later
      @customer_order.track_event "emailed", email: email
      redirect_to @customer_order, notice: "#{@customer_order.kind} emailed to #{email}.", status: :see_other
    else
      redirect_to @customer_order, alert: "Enter an email address to send it to.", status: :see_other
    end
  end
end
