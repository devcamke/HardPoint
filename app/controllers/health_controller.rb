# For the uptime monitor: 200 while the platform works, 503 when a check fails (PlatformHealth). Anyone gets the
# verdict and the checks' names; the details (counts, errors) need HEALTH_TOKEN, so they don't describe the
# platform to strangers. Served on any host, outside the shop and session machinery, like /up.
class HealthController < ActionController::API
  rate_limit to: 60, within: 1.minute

  def show
    health = PlatformHealth.check
    render json: health.as_json(detail: detailed?), status: health.ok? ? :ok : :service_unavailable
  end

  private
    def detailed?
      token = ENV["HEALTH_TOKEN"].to_s
      token.present? && ActiveSupport::SecurityUtils.secure_compare(token, params[:token].to_s)
    end
end
