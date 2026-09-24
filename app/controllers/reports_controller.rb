class ReportsController < ApplicationController
  before_action :ensure_can_view_reports

  def index
    @reports = Report::KEYS.map { Report.find(_1) }.group_by(&:group)
  end

  def show
    report_class = Report.find(params[:key]) || raise(ActiveRecord::RecordNotFound)
    @report = report_class.new(account: Current.account, period: Report::Period.from_params(params),
      branch: Current.account.branches.find_by(id: params[:branch_id]), options: report_class.options.to_h { |name, *| [ name, params[name] ] })

    respond_to do |format|
      format.html
      format.csv { send_data @report.to_csv, filename: @report.filename("csv"), type: :csv }
      format.pdf do
        pdf = ReportPdf.new(@report)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end
end
