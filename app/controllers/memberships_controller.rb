class MembershipsController < ApplicationController
  before_action :ensure_can_manage_staff
  before_action :set_membership, only: %i[ edit update destroy ]
  # Only owners hand out, change or take away the owner role: a manager can't promote themselves or remove an owner.
  before_action :ensure_owner_for_owner_roles, only: %i[ create update destroy ]
  # Nobody but an owner changes their own role or branch: a manager bound to one branch would otherwise unbind themselves.
  before_action :refuse_own_membership, only: %i[ edit update destroy ]

  def index
    @memberships = manageable_memberships.alphabetically.includes(:user)
  end

  def new
    @membership = Current.account.memberships.new
  end

  def create
    @membership = Current.account.memberships.new(membership_params)
    # Someone whose address was never confirmed is invited as if new: the login may not be theirs.
    new_user = @membership.user&.new_record? || !@membership.user&.email_confirmed?

    saved = Membership.transaction do
      @membership.save.tap { |ok| @membership.user.take_back_unconfirmed_login if ok && new_user }
    end

    if saved
      # Someone who already uses HardPoint keeps their password; they're only told where to sign in.
      MembershipsMailer.with(membership: @membership).public_send(new_user ? :invitation : :added).deliver_later
      redirect_to memberships_path, notice: "#{@membership.user.name} has been added and emailed a sign-in link."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @membership.update(bound_to_own_branch(params.expect(membership: [ :role, :branch_id ])))
      redirect_to memberships_path, notice: "Role updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @membership.destroy
      redirect_to memberships_path, notice: "#{@membership.user.name} no longer has access.", status: :see_other
    else
      redirect_to memberships_path, alert: @membership.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private
    def set_membership
      @membership = manageable_memberships.find(params[:id])
    end

    # A manager bound to a branch manages that branch's staff, and puts the people they add or change there.
    def manageable_memberships
      branch = current_membership.branch
      branch ? Current.account.memberships.where(branch: branch) : Current.account.memberships
    end

    def bound_to_own_branch(attributes)
      current_membership.bound_to_branch? ? attributes.merge(branch_id: current_membership.branch_id) : attributes
    end

    def refuse_own_membership
      return if current_membership.owner? || @membership != current_membership

      redirect_to memberships_path, alert: "Your own role and branch are changed by an owner.", status: :see_other
    end

    def ensure_owner_for_owner_roles
      return if current_membership.owner?

      if @membership&.owner? || params.dig(:membership, :role).to_s == "owner"
        redirect_to memberships_path, alert: "Only an owner can add, change or remove an owner.", status: :see_other
      end
    end

    def membership_params
      bound_to_own_branch(params.expect(membership: [ :role, :branch_id, user_attributes: %i[ name email_address ] ]))
    end
end
