class HireAgreements::CancellationsController < ApplicationController
  include HireAgreementScoped

  def create
    if @hire_agreement.cancel
      redirect_to @hire_agreement, notice: "Hire cancelled; the tools are available again.", status: :see_other
    else
      redirect_to @hire_agreement, alert: @hire_agreement.errors.full_messages.to_sentence, status: :see_other
    end
  end
end
