# Help inside a shop: guides, WhatsApp, and a message to support. Open to everyone in the shop,
# even while it's read-only.
class SupportRequestsController < ApplicationController
  allow_while_locked
  rate_limit to: 5, within: 10.minutes, only: :create, with: -> { redirect_to new_support_request_path, alert: "That's a lot of messages; try again shortly." }

  def new
    @support_request = Current.account.support_requests.new(page: params[:page].presence || safe_referer_path)
    @recent = Current.account.support_requests.where(user: Current.user).chronologically.limit(5)
  end

  def create
    @support_request = Current.account.support_requests.new(support_request_params)

    if @support_request.save
      redirect_to new_support_request_path, notice: "Sent (#{@support_request.reference}). We'll reply to #{Current.user.email_address}, usually within a working day.", status: :see_other
    else
      @recent = Current.account.support_requests.where(user: Current.user).chronologically.limit(5)
      render :new, status: :unprocessable_entity
    end
  end

  private
    def support_request_params
      params.expect(support_request: %i[ subject body page ])
    end

    def safe_referer_path
      uri = URI.parse(request.referer.to_s)
      uri.path if uri.host == request.host && uri.path != new_support_request_path
    rescue URI::InvalidURIError
      nil
    end
end
