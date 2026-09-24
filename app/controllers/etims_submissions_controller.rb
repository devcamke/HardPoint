class EtimsSubmissionsController < ApplicationController
  before_action :ensure_can_view_reports

  def index
    @status = params[:status].presence_in(Etims::Submission.statuses.keys + [ "all" ]) || "all"
    submissions = Current.account.etims_submissions.chronologically.includes(:device, :document)
    submissions = submissions.where(status: @status) unless @status == "all"
    @submissions = paginate(submissions)
    @counts = Current.account.etims_submissions.group(:status).count
  end

  def show
    @submission = Current.account.etims_submissions.find(params[:id])
  end
end
