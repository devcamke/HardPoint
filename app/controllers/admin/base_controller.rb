# The platform admin area on admin.<domain>. It deliberately doesn't inherit ApplicationController:
# there's no current shop here, and administrators sign in separately from shop staff.
class Admin::BaseController < ActionController::Base
  include AdminAuthentication

  allow_browser versions: :modern
  layout "admin"

  private
    # Administrators work across shops, so tenant row-level security is bypassed for their requests.
    def across_accounts(&)
      Account.without_isolation(&)
    end
end
