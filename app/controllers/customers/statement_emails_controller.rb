class Customers::StatementEmailsController < ApplicationController
  include StatementPeriod
  before_action :ensure_can_manage_receivables, :set_customer_and_statement

  def create
    if @customer.email.present?
      pdf = statement_pdf
      CustomersMailer.with(customer: @customer, pdf: pdf.render, filename: pdf.filename, from: @statement.from, to: @statement.to,
        balance_cents: @statement.closing_balance_cents, sender: Current.user).statement.deliver_later
      @customer.track_event "statement_emailed", email: @customer.email, to: @statement.to.iso8601
      redirect_to customer_statement_path(@customer, from: @statement.from, to: @statement.to), notice: "Statement emailed to #{@customer.email}.", status: :see_other
    else
      redirect_to customer_statement_path(@customer, from: @statement.from, to: @statement.to), alert: "Add #{@customer.name}'s email address first.", status: :see_other
    end
  end
end
