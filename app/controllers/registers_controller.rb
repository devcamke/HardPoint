class RegistersController < ApplicationController
  before_action :ensure_can_manage_branches, except: :index
  before_action :set_register, only: %i[ edit update destroy ]

  def index
    @registers = Current.account.registers.ordered
  end

  def new
    @register = Current.account.registers.new(branch: Current.account.branches.find_by(id: params[:branch_id]))
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
      @register = Current.account.registers.find(params[:id])
    end

    # The branch is looked up through the account, so a till can't be attached to another shop's branch.
    def register_params
      params.expect(register: %i[ name branch_id active ]).tap do |permitted|
        permitted[:branch] = Current.account.branches.find(permitted.delete(:branch_id)) if permitted.key?(:branch_id)
      end
    end
end
