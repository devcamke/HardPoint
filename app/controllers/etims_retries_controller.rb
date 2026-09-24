# Sends every refused submission again, once whatever KRA objected to has been fixed.
class EtimsRetriesController < ApplicationController
  before_action :ensure_can_view_reports

  def create
    failed = Current.account.etims_submissions.failed.to_a
    failed.each(&:retry_now)
    redirect_to etims_submissions_path, notice: "Sending #{helpers.pluralize(failed.size, "submission")} to KRA again.", status: :see_other
  end
end
