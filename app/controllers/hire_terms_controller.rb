# The terms printed on the shop's tool-hire agreements. Owners and managers change them; each agreement
# keeps the terms it was made under, so an edit only affects agreements made from now on.
class HireTermsController < ApplicationController
  before_action :ensure_approver

  def edit
  end

  def update
    Current.account.hire_terms = params[:reset] ? nil : params.dig(:account, :hire_terms)

    if Current.account.save
      redirect_to edit_hire_terms_path, status: :see_other,
        notice: Current.account.own_hire_terms? ? "Hire terms saved. New agreements print them; earlier ones keep the terms they were signed with." : "Back to the standard hire terms."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end
end
