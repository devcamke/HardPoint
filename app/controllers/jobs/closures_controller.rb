# Closing a finished job takes it off the till's list; reopening puts it back. A job with orders still to
# be collected stays open until they're collected, cancelled or moved.
class Jobs::ClosuresController < ApplicationController
  before_action :ensure_can_sell

  def create
    job = Current.account.jobs.find(params[:job_id])
    if job.close
      redirect_to job, notice: "#{job.name} closed. It no longer shows at the till."
    else
      redirect_to job, alert: job.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    job = Current.account.jobs.find(params[:job_id])
    job.reopen
    redirect_to job, notice: "#{job.name} reopened."
  end
end
