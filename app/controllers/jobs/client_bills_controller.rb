# The materials bill a contractor hands their own client, as an A4 PDF on the contractor's letterhead.
class Jobs::ClientBillsController < ApplicationController
  before_action :ensure_can_sell_or_manage_receivables

  def show
    pdf = JobClientBillPdf.new(Current.account.jobs.includes(:customer).find(params[:job_id]))
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end
end
