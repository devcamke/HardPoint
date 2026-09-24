# Safaricom's answers to prompts for HardPoint subscription payments. The URL carries the
# platform's secret token; the payment is found by its checkout ID. Always answered with ResultCode 0.
class Webhooks::BillingMpesaController < ActionController::API
  before_action :verify_source_ip, :verify_token

  def create
    Billing::MpesaShortcode.new.receive_stk_callback(JSON.parse(request.raw_post))
    render json: { ResultCode: 0, ResultDesc: "Accepted" }
  rescue JSON::ParserError
    render json: { ResultCode: 0, ResultDesc: "Accepted" }
  end

  private
    def verify_token
      expected = Billing::MpesaShortcode.new.callback_token
      head :not_found unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(request.path_parameters[:token].to_s, expected)
    end

    def verify_source_ip
      allowed = Rails.configuration.x.mpesa_callback_ips
      head :forbidden if allowed.present? && allowed.none? { _1.include?(request.remote_ip) }
    end
end
