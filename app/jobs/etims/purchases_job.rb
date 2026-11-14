# Each morning, asks KRA what suppliers have invoiced each shop since its control units last asked (Etims::Purchase),
# so the invoices are waiting under Buy › From KRA when the goods arrive. One job per shop, so a slow answer for one
# doesn't hold up the rest.
class Etims::PurchasesJob < ApplicationJob
  def perform(account = nil)
    return fetch_for(account) if account

    shops = Account.without_isolation { Etims::Device.active.where.not(cmc_key: nil).distinct.pluck(:account_id) }
    Account.where(id: shops).find_each do |shop|
      Current.set(account: shop) { self.class.perform_later(shop) }
    end
  end

  private
    def fetch_for(account)
      Current.set(account: account) { account.etims_devices.active.select(&:initialized?).each { Etims::Purchase.fetch(_1) } }
    end
end
