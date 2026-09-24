class BranchesController < ApplicationController
  before_action :ensure_can_manage_branches, except: :index
  before_action :set_branch, only: %i[ edit update destroy ]

  def index
    @branches = Current.account.branches.alphabetically
  end

  def new
    @branch = Current.account.branches.new
  end

  def create
    @branch = Current.account.branches.new(branch_params)

    if @branch.save
      redirect_to branches_path, notice: "Branch added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @branch.update(branch_params)
      redirect_to branches_path, notice: "Branch updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @branch.destroy
      redirect_to branches_path, notice: "Branch removed.", status: :see_other
    else
      redirect_to edit_branch_path(@branch), alert: @branch.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def set_branch
      @branch = Current.account.branches.find(params[:id])
    end

    def branch_params
      params.expect(branch: %i[ name address phone ])
    end
end
