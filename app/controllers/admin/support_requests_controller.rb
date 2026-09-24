class Admin::SupportRequestsController < Admin::BaseController
  around_action :across_accounts

  def index
    @status = params[:status].presence_in(%w[ open resolved all ]) || "open"
    @support_requests = SupportRequest.chronologically.includes(:account, :user).limit(100)
    @support_requests = @support_requests.where(status: @status) unless @status == "all"
  end

  def update
    support_request = SupportRequest.find(params[:id])
    support_request.update!(status: params[:status].presence_in(SupportRequest.statuses.keys) || "resolved")
    redirect_to admin_support_requests_path, notice: "#{support_request.reference} marked #{support_request.status}.", status: :see_other
  end
end
