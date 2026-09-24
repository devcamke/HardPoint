class Sales::ReceiptTextsController < ApplicationController
  include SaleScoped
  rate_limit to: 100, within: 10.minutes, only: :create, by: -> { Current.account.id }, with: -> { redirect_back_or_to sale_path(@sale), alert: "Try again later." }

  def create
    text = Sms::Message.receipt(@sale, to: params[:phone]) if @sale.completed?

    if text&.persisted?
      redirect_back_or_to sale_path(@sale), notice: "Receipt texted to #{PhoneNumber.display(text.recipient)}."
    else
      redirect_back_or_to sale_path(@sale), alert: text&.errors&.full_messages&.to_sentence || "Only a completed sale has a receipt."
    end
  end
end
