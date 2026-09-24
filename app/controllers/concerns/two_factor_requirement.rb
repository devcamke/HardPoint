# Shops can require owners and managers to use two-factor sign-in; until they turn it on,
# they're sent to set it up.
module TwoFactorRequirement
  extend ActiveSupport::Concern

  included do
    before_action :require_two_factor_setup
  end

  class_methods do
    def allow_without_two_factor(**options)
      skip_before_action :require_two_factor_setup, **options
    end
  end

  private
    def require_two_factor_setup
      if Current.membership&.two_factor_required? && !Current.user.two_factor_enabled? && !Current.session.impersonated?
        redirect_to new_my_two_factor_path, alert: "#{Current.account.name} requires two-factor sign-in for owners and managers. Set it up to continue."
      end
    end
end
