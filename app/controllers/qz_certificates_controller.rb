# The certificate QZ Tray checks a till's print requests against: the shop's own (Account::QzSigning), issued
# under the platform's QZ certificate when there is one so QZ Tray asks nothing, self-signed otherwise so QZ Tray
# asks the cashier once per till to trust it.
class QzCertificatesController < ApplicationController
  before_action :ensure_can_sell

  def show
    render plain: Current.account.qz_certificate_chain
  end
end
