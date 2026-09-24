class Sales::ReceiptEmailsController < ApplicationController
  include SaleScoped
  rate_limit to: 20, within: 10.minutes, only: :create, with: -> { redirect_back_or_to sale_path(@sale), alert: "Try again later." }

  def create
    email = params[:email].to_s.strip

    if email.match?(URI::MailTo::EMAIL_REGEXP) && @sale.completed?
      SalesMailer.with(sale: @sale, email: email).receipt.deliver_later
      @sale.customer.update(email: email) if @sale.customer && @sale.customer.email.blank?
      redirect_back_or_to sale_path(@sale), notice: "Receipt emailed to #{email}."
    else
      redirect_back_or_to sale_path(@sale), alert: "Enter a valid email address."
    end
  end
end
