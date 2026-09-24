class Pos::TillsController < ApplicationController
  before_action :ensure_can_sell

  def new
    @registers = Current.account.registers.active.ordered
  end

  def create
    remember_till Current.account.registers.active.find(params[:register_id])
    redirect_to pos_path
  end
end
