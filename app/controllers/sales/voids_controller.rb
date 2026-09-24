# Cancelling a completed sale during its shift. Needs an owner or manager.
class Sales::VoidsController < ApplicationController
  include SaleScoped

  def new
    redirect_to @sale, alert: "Only a completed sale in a shift that's still open can be voided. Use a return instead." unless @sale.voidable?
  end

  def create
    approver = approver_for_action

    if params[:reason].blank?
      flash.now[:alert] = "Say why the sale is being voided."
      render :new, status: :unprocessable_entity
    elsif approver.nil?
      flash.now[:alert] = "Voiding needs a manager's approval PIN."
      render :new, status: :unprocessable_entity
    elsif @sale.void(reason: params[:reason], approver: approver)
      redirect_to @sale, notice: "Sale voided. Stock is back and it no longer counts in the shift's takings — give back any money received."
    else
      redirect_to @sale, alert: "This sale can't be voided."
    end
  end
end
