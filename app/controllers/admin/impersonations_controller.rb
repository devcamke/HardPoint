class Admin::ImpersonationsController < Admin::BaseController
  def create
    membership = Account.without_isolation { Membership.includes(:account, :user).find(params[:membership_id]) }
    impersonation = Impersonation.issue(administrator: current_administrator, membership: membership, ip_address: request.remote_ip)

    redirect_to new_session_impersonation_url(subdomain: membership.account.subdomain, token: impersonation.token), allow_other_host: true
  end
end
