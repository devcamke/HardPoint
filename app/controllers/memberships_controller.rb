class MembershipsController < ApplicationController
  before_action :ensure_can_manage_staff
  before_action :set_membership, only: %i[ edit update destroy ]
  # Only owners hand out, change or take away the owner role: a manager can't promote themselves or remove an owner.
  before_action :ensure_owner_for_owner_roles, only: %i[ create update destroy ]

  def index
    @memberships = Current.account.memberships.alphabetically.includes(:user)
  end

  def new
    @membership = Current.account.memberships.new
  end

  def create
    @membership = Current.account.memberships.new(membership_params)
    new_user = @membership.user&.new_record?

    if @membership.save
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
    if @membership.update(params.expect(membership: [ :role, :branch_id ]))
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
      @membership = Current.account.memberships.find(params[:id])
    end

    def ensure_owner_for_owner_roles
      return if current_membership.owner?

      if @membership&.owner? || params.dig(:membership, :role).to_s == "owner"
        redirect_to memberships_path, alert: "Only an owner can add, change or remove an owner.", status: :see_other
      end
    end

    def membership_params
      params.expect(membership: [ :role, :branch_id, user_attributes: %i[ name email_address ] ])
    end
end
