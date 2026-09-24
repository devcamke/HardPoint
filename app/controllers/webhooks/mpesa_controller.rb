# Safaricom's callbacks. The shop is found from the secret token in the URL (each shortcode has
# its own), never from anything in the payload; requests must come from Safaricom's addresses
# when those are configured; and every callback is safe to receive twice. Safaricom expects a
# 200 with ResultCode 0 whatever we make of the payload, or it keeps retrying.
class Webhooks::MpesaController < ActionController::API
  before_action :verify_source_ip, :set_shortcode
  rate_limit to: 300, within: 1.minute, by: -> { token }

  def stk
    @shortcode.receive_stk_callback(payload)
    accepted
  end

  def confirmation
    @shortcode.receive_c2b_confirmation(payload)
    accepted
  end

  # Every payment to the Paybill is accepted; unrecognised ones are matched by hand at the till.
  def validation
    accepted
  end

  private
    def set_shortcode
      shortcode = Account.without_isolation { Mpesa::Shortcode.active.find_by(callback_token: token) }
      return head(:not_found) unless shortcode

      Current.account = shortcode.account
      @shortcode = shortcode
    end

    def verify_source_ip
      allowed = Rails.configuration.x.mpesa_callback_ips
      head :forbidden if allowed.present? && allowed.none? { _1.include?(request.remote_ip) }
    end

    # From the path, not params: params would parse the body, and a body that isn't JSON must
    # still get Safaricom its 200.
    def token
      request.path_parameters[:token].to_s
    end

    def payload
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end

    def accepted
      render json: { ResultCode: 0, ResultDesc: "Accepted" }
    end
end
