# QZ Tray prints without asking at every receipt only for sites that sign their requests. The
# certificate (public) and private key live in the credentials under qz: { certificate:, private_key: };
# without them QZ Tray still prints, after asking the cashier to allow it.
class QzCertificatesController < ApplicationController
  before_action :ensure_can_sell

  def show
    certificate = QzSignaturesController.keys[:certificate]
    certificate ? render(plain: certificate) : head(:not_found)
  end
end
