# The period a customer statement covers: this month so far unless chosen.
module StatementPeriod
  extend ActiveSupport::Concern

  private
    def set_customer_and_statement
      @customer = Current.account.customers.find(params[:customer_id])
      from = (Date.parse(params[:from]) rescue Date.current.beginning_of_month)
      to = (Date.parse(params[:to]) rescue Date.current)
      @statement = @customer.statement(from: from, to: to)
    end

    def statement_pdf
      StatementPdf.new(@statement, branch: current_till&.branch || selected_branch || Current.account.branches.first)
    end
end
