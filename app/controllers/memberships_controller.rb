class MembershipsController < ApplicationController
  before_action :ensure_can_manage_staff
  before_action :set_membership, only: %i[ edit update destroy ]

  def index
    @memberships = Current.account.memberships.alphabetically.includes(:user)
  end

  def new
    @membership = Current.account.memberships.new
  end

  def create
    @membership = Current.account.memberships.new(membership_params)

    if @membership.save
      MembershipsMailer.with(membership: @membership).invitation.deliver_later
      redirect_to memberships_path, notice: "#{@membership.user.name} has been added and emailed a sign-in link."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @membership.update(params.expect(membership: [ :role ]))
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

    def membership_params
      params.expect(membership: [ :role, user_attributes: %i[ name email_address ] ])
    end
end
