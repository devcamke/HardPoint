# Which document a share or WhatsApp send is for (params kind and id), and whether this member of staff may hand
# it out: only staff who could open it themselves may, the role that works with it, at a branch they see.
module SharedDocument
  extend ActiveSupport::Concern

  ALLOWED = { "Sale" => :can_sell?, "CustomerOrder" => :can_sell?, "DeliveryNote" => :can_sell?, "SaleReturn" => :can_sell?,
              "PurchaseOrder" => :can_purchase?, "Customer" => :can_manage_receivables? }.freeze

  private
    def set_document
      model = DocumentShare::KINDS.fetch(params[:kind].to_s) { return head(:not_found) }
      @document = model.constantize.where(account: Current.account).find(params[:id])
      head :not_found unless allowed_document?(@document)
    end

    def allowed_document?(document)
      return false unless current_membership&.public_send(SharedDocument::ALLOWED.fetch(document.class.name))
      return true unless document.has_attribute?(:branch_id) && current_membership.bound_to_branch?

      document.branch_id == current_membership.branch_id
    end

    def period(name)
      Date.iso8601(params[name].to_s) if params[name].present?
    rescue Date::Error
      nil
    end
end
