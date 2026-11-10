# Cash in or out of a till's drawer that isn't a sale: only on the till this device is set to, since that's the
# drawer the cash is in, and a payout above the shop's limit needs an owner or manager, at the till or by approval PIN.
class Shifts::CashMovementsController < ApplicationController
  before_action :ensure_can_sell, :set_shift

  def new
    @movement = @shift.cash_movements.new(kind: params[:kind].presence_in(CashMovement::KINDS) || "drop")
  end

  def create
    @movement = @shift.cash_movements.new(params.expect(cash_movement: %i[ kind amount reason supplier_id ]).merge(account: Current.account))
    approver = approver_for_action if @movement.needs_approval?

    if @movement.valid? && @movement.needs_approval? && approver.nil?
      @movement.errors.add :base, "A payout over #{Money.format(Current.account.payout_approval_above_cents)} needs a manager's approval PIN"
      render :new, status: :unprocessable_entity
    elsif @movement.save
      @shift.track_event "payout_approved", approver: approver, amount: @movement.amount_cents, reason: @movement.reason if approver
      redirect_to shift_path(@shift), notice: "#{@movement.kind.humanize} of #{Money.format(@movement.amount_cents)} recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    # The open shift of the till this device is set to, and no other's.
    def set_shift
      @shift = current_shift
      raise ActiveRecord::RecordNotFound unless @shift && @shift.id == params[:shift_id].to_i
    end
end
