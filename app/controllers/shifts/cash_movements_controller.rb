class Shifts::CashMovementsController < ApplicationController
  before_action :ensure_can_sell, :set_shift

  def new
    @movement = @shift.cash_movements.new(kind: params[:kind].presence_in(CashMovement::KINDS) || "drop")
  end

  def create
    @movement = @shift.cash_movements.new(params.expect(cash_movement: %i[ kind amount reason ]).merge(account: Current.account))

    if @movement.save
      redirect_to shift_path(@shift), notice: "#{@movement.kind.humanize} of #{Money.format(@movement.amount_cents)} recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_shift
      @shift = Current.account.shifts.open.find(params[:shift_id])
    end
end
