class HireAgreements::RemindersController < ApplicationController
  include HireAgreementScoped

  def create
    if @hire_agreement.remind
      redirect_to @hire_agreement, notice: "Reminder texted to #{@hire_agreement.customer.name}.", status: :see_other
    else
      redirect_to @hire_agreement, alert: "No reminder sent: it isn't overdue, SMS is off, or one went out in the last day.", status: :see_other
    end
  end
end
