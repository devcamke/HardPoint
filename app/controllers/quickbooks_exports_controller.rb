# Reports › QuickBooks export: a month of the books as files QuickBooks Online imports (QuickbooksExport),
# and the account names they post to.
class QuickbooksExportsController < ApplicationController
  before_action :ensure_can_view_reports, :ensure_sees_every_branch

  def show
    @month = (Date.strptime(params[:month].to_s, "%Y-%m") rescue Date.current.prev_month).beginning_of_month
    @account_names = QuickbooksExport.account_names(Current.account)

    respond_to do |format|
      format.html
      format.zip do
        export = QuickbooksExport.new(Current.account, month: @month)
        Current.account.track_event "quickbooks_exported", month: @month.strftime("%B %Y")
        send_data export.to_zip, filename: export.filename, type: "application/zip"
      end
    end
  end

  def update
    names = params.fetch(:accounts, {}).permit(*QuickbooksExport::ACCOUNTS.keys).to_h.transform_values(&:squish)
      .reject { |key, name| name.blank? || name == QuickbooksExport::ACCOUNTS.fetch(key).last }
    Current.account.update!(quickbooks_accounts: names)
    redirect_to quickbooks_export_path(month: params[:month]), notice: "QuickBooks account names saved.", status: :see_other
  end

  private
    # The export is the whole shop's books, which can't be split by branch, so it's for those who see every branch.
    def ensure_sees_every_branch
      return unless current_membership.bound_to_branch?

      redirect_to reports_path, alert: "The QuickBooks export covers the whole shop's books, so only staff who see every branch can download it. Ask the owner.",
        status: :see_other
    end
end
