class BranchesController < ApplicationController
  before_action :ensure_can_manage_branches, except: :index
  # A manager bound to one branch looks after that branch; opening and closing branches is for staff who see them all.
  before_action :ensure_sees_every_branch, only: %i[ new create destroy ]
  before_action :set_branch, only: %i[ edit update destroy ]

  def index
    @branches = visible_branches.alphabetically
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
      @branch = visible_branches.find(params[:id])
    end

    def ensure_sees_every_branch
      head :forbidden if current_membership.bound_to_branch?
    end

    def branch_params
      params.expect(branch: %i[ name code address phone ])
    end
end
