# The link to a customer's own page (PortalLink): made (or the current one reused) and sent on WhatsApp from the
# customer's page, or taken back so it stops opening.
class Customers::PortalLinksController < ApplicationController
  before_action :ensure_can_manage_receivables
  before_action { head :not_found unless Current.account.feature?(:customer_portal) }
  before_action { @customer = Current.account.customers.find(params[:customer_id]) }

  def create
    link = PortalLink.for(@customer)
    if params[:send] == "whatsapp"
      redirect_to "https://wa.me/#{PhoneNumber.normalize(params[:phone] || @customer.phone)}?#{{ text: link.message }.to_query}", allow_other_host: true
    else
      redirect_to customer_path(@customer, anchor: "portal"), notice: "The customer's portal link is ready to copy.", status: :see_other
    end
  end

  def destroy
    @customer.portal_links.current.find_each(&:revoke)
    redirect_to customer_path(@customer, anchor: "portal"), notice: "The portal link no longer opens anything. Send a new one when you're ready.", status: :see_other
  end
end
