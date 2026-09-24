class HireAgreements::ExtensionsController < ApplicationController
  include HireAgreementScoped

  def create
    if @hire_agreement.extend_to(Time.zone.parse(params[:due_back_at].to_s) || Time.current)
      redirect_to @hire_agreement, notice: "Due back #{helpers.l(@hire_agreement.due_back_at, format: :short)} now.", status: :see_other
    else
      redirect_to @hire_agreement, alert: @hire_agreement.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
