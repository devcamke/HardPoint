module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_membership, :visible_branches
  end

  private
    def current_membership
      Current.membership
    end

    # The branches the signed-in member may see. Staff bound to a branch see nothing of the others: not its
    # tills, sales, shifts, returns, orders, deliveries, stock counts or reports.
    def visible_branches
      current_membership&.visible_branches || Current.account.branches
    end

    # A relation of records that belong to a branch, cut down to what the member may see.
    def within_visible_branches(relation, column = :branch_id)
      current_membership&.bound_to_branch? ? relation.where(column => current_membership.branch_id) : relation
    end

    # Stock transfers that touch a branch the member may see, at either end.
    def visible_transfers
      transfers = Current.account.stock_transfers
      return transfers unless current_membership&.bound_to_branch?

      transfers.where(from_branch_id: current_membership.branch_id).or(transfers.where(to_branch_id: current_membership.branch_id))
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

    def ensure_can_purchase
      head :forbidden unless current_membership&.can_purchase?
    end

    def ensure_can_manage_payables
      head :forbidden unless current_membership&.can_manage_payables?
    end

    def ensure_can_purchase_or_pay
      head :forbidden unless current_membership&.can_purchase? || current_membership&.can_manage_payables?
    end

    def ensure_can_sell
      head :forbidden unless current_membership&.can_sell?
    end

    def ensure_can_view_reports
      head :forbidden unless current_membership&.can_view_reports?
    end

    def ensure_can_manage_receivables
      head :forbidden unless current_membership&.can_manage_receivables?
    end

    def ensure_can_sell_or_manage_receivables
      head :forbidden unless current_membership&.can_sell? || current_membership&.can_manage_receivables?
    end

    # Owners and managers approve their own actions; anyone else needs one of them to type an approval PIN. With
    # "require a second approver" on, an owner's or manager's own action needs someone else's PIN.
    def approver_for_action
      return Current.user if current_membership&.approves_own_actions?

      approver = Approval.approver_for(Current.account, params[:approval_pin])
      approver unless approver == Current.user && current_membership&.approver?
    end

    def ensure_can_approve_stock_counts
      head :forbidden unless current_membership&.can_approve_stock_counts?
    end
end
