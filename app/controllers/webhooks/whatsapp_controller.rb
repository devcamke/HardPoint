# Meta's webhook for HardPoint's WhatsApp number. GET is Meta checking the address (it must send our verify token);
# POST carries status updates (sent, delivered, read, failed), trusted only with a valid X-Hub-Signature-256: an
# HMAC-SHA256 of the raw body with the app secret. Updates name Meta's message id, matched across shops.
class Webhooks::WhatsappController < ActionController::API
  def show
    if params["hub.mode"] == "subscribe" && Whatsapp.verify_token.present? &&
        ActiveSupport::SecurityUtils.secure_compare(params["hub.verify_token"].to_s, Whatsapp.verify_token)
      render plain: params["hub.challenge"].to_s
    else
      head :forbidden
    end
  end

  def create
    return head(:unauthorized) unless valid_signature?

    statuses.each do |status|
      message = Account.without_isolation { Whatsapp::Message.find_by(provider_message_id: status["id"].to_s) } or next
      Current.set(account: message.account) do
        message.record_status(status["status"].to_s, at: Time.zone.at(status["timestamp"].to_i), error: status.dig("errors", 0, "title"))
      end
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private
    def valid_signature?
      secret = Whatsapp.app_secret
      sent = request.headers["X-Hub-Signature-256"].to_s
      secret.present? && sent.start_with?("sha256=") &&
        ActiveSupport::SecurityUtils.secure_compare(sent, "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)}")
    end

    def statuses
      Array(JSON.parse(request.raw_post)["entry"]).flat_map { |entry| Array(entry["changes"]) }
        .flat_map { |change| Array(change.dig("value", "statuses")) }
    end
end
