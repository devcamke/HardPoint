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

    def ensure_can_manage_catalogue
      head :forbidden unless current_membership&.can_manage_catalogue?
    end

    def ensure_can_manage_stock
      head :forbidden unless current_membership&.can_manage_stock?
    end

    def ensure_can_sell
      head :forbidden unless current_membership&.can_sell?
    end

    # Owners and managers approve their own actions; anyone else needs one of them to type an approval PIN.
    def approver_for_action
      current_membership&.approver? ? Current.user : Approval.approver_for(Current.account, params[:approval_pin])
    end

    def ensure_can_approve_stock_counts
      head :forbidden unless current_membership&.can_approve_stock_counts?
    end
end
