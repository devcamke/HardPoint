module HireAgreementScoped
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_sell
    before_action :set_hire_agreement
  end

  private
    def set_hire_agreement
      @hire_agreement = Current.account.hire_agreements.find(params[:hire_agreement_id] || params[:id])
    end
end
