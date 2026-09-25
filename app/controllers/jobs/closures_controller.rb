# Closing a finished job takes it off the till's list; reopening puts it back.
class Jobs::ClosuresController < ApplicationController
  before_action :ensure_can_sell

  def create
    job = Current.account.jobs.find(params[:job_id])
    job.close
    redirect_to job, notice: "#{job.name} closed. It no longer shows at the till."
  end

  def destroy
    job = Current.account.jobs.find(params[:job_id])
    job.reopen
    redirect_to job, notice: "#{job.name} reopened."
  end
end
