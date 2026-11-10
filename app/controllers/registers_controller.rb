class RegistersController < ApplicationController
  before_action :ensure_can_manage_branches, except: :index
  before_action :set_register, only: %i[ edit update destroy ]

  def index
    @registers = within_visible_branches(Current.account.registers).ordered
  end

  def new
    @register = Current.account.registers.new(branch: visible_branches.find_by(id: params[:branch_id]) || (current_membership.branch if current_membership.bound_to_branch?))
  end

  def create
    @register = Current.account.registers.new(register_params)

    if @register.save
      redirect_to registers_path, notice: "Till added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @register.update(register_params)
      redirect_to registers_path, notice: "Till updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @register.destroy
    redirect_to registers_path, notice: "Till removed.", status: :see_other
  end

  private
    def set_register
      @register = within_visible_branches(Current.account.registers).find(params[:id])
    end

    # The branch is looked up among those the member sees, so a till can't be put in another shop's branch,
    # nor by a manager bound to one branch in another.
    def register_params
      params.expect(register: %i[ name branch_id active print_mode printer_name receipt_width opens_till ]).tap do |permitted|
        permitted[:branch] = visible_branches.find(permitted.delete(:branch_id)) if permitted.key?(:branch_id)
      end
    end
end
