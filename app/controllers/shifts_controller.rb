class ShiftsController < ApplicationController
  before_action :ensure_can_sell

  def index
    shifts = Current.account.shifts.chronologically.includes(:register, :branch, :opened_by, :closed_by)
    shifts = shifts.where(register: current_till) unless current_membership.approver? || current_till.nil?
    @shifts = paginate(shifts)
  end

  def show
    @shift = Current.account.shifts.find(params[:id])
    @report = @shift.report
  end

  def new
    return redirect_to new_pos_till_path if current_till.nil?
    return redirect_to pos_path if current_shift

    @shift = Current.account.shifts.new(register: current_till)
  end

  def create
    @shift = Current.account.shifts.new(register: current_till, opening_float: params.dig(:shift, :opening_float))

    if @shift.save
      redirect_to pos_path, notice: "Shift open. Float #{Money.format(@shift.opening_float_cents)}."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
