class EtimsSubmissions::RetriesController < ApplicationController
  before_action :ensure_can_view_reports

  def create
    submission = Current.account.etims_submissions.find(params[:etims_submission_id])
    submission.retry_now
    redirect_to etims_submission_path(submission), notice: "Sending to KRA again.", status: :see_other
  end
end
