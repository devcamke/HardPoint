class Customers::StatementsController < ApplicationController
  include StatementPeriod
  before_action :ensure_can_manage_receivables, :set_customer_and_statement

  def show
    respond_to do |format|
      format.html
      format.pdf do
        pdf = statement_pdf
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end
end
