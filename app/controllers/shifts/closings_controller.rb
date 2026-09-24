# Closing a shift with a blind count: the cashier counts the drawer without seeing what's expected.
class Shifts::ClosingsController < ApplicationController
  before_action :ensure_can_sell, :set_shift

  def new
  end

  def create
    if @shift.close(counted_cash_cents: Monetary.to_cents(params[:counted_cash]).to_i, note: params[:note])
      redirect_to shift_path(@shift), notice: "Shift closed."
    else
      flash.now[:alert] = @shift.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_shift
      @shift = Current.account.shifts.open.find(params[:shift_id])
    end
end
