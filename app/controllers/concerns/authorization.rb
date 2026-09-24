module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_membership
  end

  private
    def current_membership
      Current.membership
    end

    def ensure_can_manage_account
      head :forbidden unless current_membership&.can_manage_account?
    end

    def ensure_can_manage_staff
      head :forbidden unless current_membership&.can_manage_staff?
    end

    def ensure_can_manage_branches
      head :forbidden unless current_membership&.can_manage_branches?
    end
end
