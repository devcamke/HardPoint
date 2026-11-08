# Airtel's callbacks. The shop is found from the secret token in the URL (each merchant has its own), never
# from anything in the payload, and a callback is safe to receive twice. Airtel gets a 200 whatever we make
# of it, or it keeps retrying; the till also asks Airtel, so a callback that's lost or refused costs nothing.
class Webhooks::AirtelController < ActionController::API
  before_action :verify_source_ip, :set_merchant
  rate_limit to: 300, within: 1.minute, by: -> { token }

  def create
    @merchant.receive_callback(payload)
    head :ok
  end

  private
    # Airtel doesn't publish its callback addresses, so this list is empty unless AIRTEL_CALLBACK_IPS is set; a
    # "paid" callback is confirmed with Airtel either way (Airtel::Merchant#receive_callback).
    def verify_source_ip
      allowed = Rails.configuration.x.airtel_callback_ips
      head :forbidden if allowed.present? && allowed.none? { _1.include?(request.remote_ip) }
    end

    def set_merchant
      merchant = Account.without_isolation { Airtel::Merchant.active.find_by(callback_token: token) }
      return head(:not_found) unless merchant

      Current.account = merchant.account
      @merchant = merchant
    end

    def token
      request.path_parameters[:token].to_s
    end

    def payload
      JSON.parse(request.raw_post)
    rescue JSON::ParserError
      {}
    end
end
