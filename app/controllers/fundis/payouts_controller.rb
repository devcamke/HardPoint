# Paying a fundi the commission they're owed: owners and managers only, in cash from an open till or by M-Pesa.
class Fundis::PayoutsController < ApplicationController
  before_action :ensure_approver
  before_action :set_fundi

  def new
    @payout = @fundi.payouts.new(amount_cents: [ @fundi.balance_cents, 0 ].max, payment_method: "mobile_money")
    @shifts = open_shifts
  end

  def create
    @payout = @fundi.payouts.new(payout_params.merge(account: Current.account, paid_by: Current.user))
    @payout.shift = open_shifts.find { _1.id == params.dig(:fundi_payout, :shift_id).to_i }
    if @payout.save
      redirect_to @fundi, notice: "#{Money.format(@payout.amount_cents)} paid to #{@fundi.name} (#{@payout.method_name.downcase})."
    else
      @shifts = open_shifts
      render :new, status: :unprocessable_entity
    end
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end

    def set_fundi
      @fundi = Current.account.fundis.find(params[:fundi_id])
    end

    def open_shifts
      within_visible_branches(Current.account.shifts.open.includes(:register, :branch)).to_a
    end

    def payout_params
      params.expect(fundi_payout: %i[ amount payment_method reference note ])
    end
end
