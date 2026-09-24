class Admin::ImpersonationsController < Admin::BaseController
  def create
    membership = Account.without_isolation { Membership.includes(:account).find(params[:membership_id]) }
    impersonation = Impersonation.new(administrator: current_administrator, membership: membership)

    redirect_to new_session_impersonation_url(subdomain: membership.account.subdomain, token: impersonation.token), allow_other_host: true
  end
end
