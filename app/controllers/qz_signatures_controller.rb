# Signs what QZ Tray asks to be signed (SHA-512 with RSA), so it trusts the till's print requests.
class QzSignaturesController < ApplicationController
  before_action :ensure_can_sell
  rate_limit to: 600, within: 1.minute

  def self.keys
    Rails.configuration.x.qz.presence || Rails.application.credentials.qz || {}
  end

  def create
    key = self.class.keys[:private_key] or return head(:not_found)
    signature = OpenSSL::PKey::RSA.new(key).sign(OpenSSL::Digest.new("SHA512"), params[:request].to_s)
    render plain: Base64.strict_encode64(signature)
  end
end
