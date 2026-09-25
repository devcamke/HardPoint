# The job's cost summary as an A4 PDF, for the contractor to keep or hand to their own client.
class Jobs::SummariesController < ApplicationController
  before_action :ensure_can_sell_or_manage_receivables

  def show
    pdf = JobPdf.new(Current.account.jobs.find(params[:job_id]))
    send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
  end
end
