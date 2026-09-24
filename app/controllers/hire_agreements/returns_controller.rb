class HireAgreements::ReturnsController < ApplicationController
  include HireAgreementScoped
  before_action { redirect_to @hire_agreement, alert: "Everything on this hire is already back." unless @hire_agreement.out? }

  def new
  end

  def create
    returns = params.fetch(:returns, {}).to_unsafe_h.select { |_, line| line[:back] == "1" }
    return redirect_to(new_hire_agreement_return_path(@hire_agreement), alert: "Tick the tools that came back.") if returns.empty?

    @hire_agreement.return_tools(returns.transform_values(&:symbolize_keys))
    if @hire_agreement.returned?
      redirect_to @hire_agreement, notice: "All back. Settle #{helpers.money(@hire_agreement.charges_cents)} at the till.", status: :see_other
    else
      redirect_to @hire_agreement, notice: "#{helpers.pluralize(returns.size, "tool")} back; the rest are still out.", status: :see_other
    end
  end
end
