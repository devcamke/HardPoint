# Where an administrator's signed impersonation link lands, on the shop's own subdomain.
class Sessions::ImpersonationsController < ApplicationController
  allow_while_locked
  allow_unauthenticated_access
  allow_without_two_factor
  before_action :set_impersonation

  def new
  end

  def create
    terminate_session if authenticated?
    start_new_session_for @impersonation.membership.user, sign_in_method: :impersonation, impersonator: @impersonation.administrator
    redirect_to root_path
  end

  private
    def set_impersonation
      @impersonation = Impersonation.from_token(params[:token])
      redirect_to new_session_path, alert: "That support link is invalid or has expired." unless @impersonation
    end
end
