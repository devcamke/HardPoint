# Completing a sale that comes to nothing (a replacement under warranty discounted to zero, a free item on its own):
# there's no payment to complete it through, so an owner or manager does, at the till or by approval PIN.
class Pos::CompletionsController < ApplicationController
  include PosSale

  def create
    approver = approver_for_action

    if approver.nil?
      render_cart alert: "Completing a sale with nothing to pay needs a manager's approval PIN", status: :unprocessable_entity
    elsif @sale.complete_without_payment(approver: approver)
      redirect_to pos_path(completed: @sale.id), status: :see_other
    else
      render_cart alert: @sale.errors.full_messages.to_sentence, status: :unprocessable_entity
    end
  end
end
