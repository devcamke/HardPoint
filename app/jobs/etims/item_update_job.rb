# A product's name or tax rate changed: each control unit that registered it with KRA registers it again,
# so KRA's item isn't left with the old name or tax type. If KRA can't take it now, the registration is
# forgotten and the product's next sale registers it again before the invoice goes.
class Etims::ItemUpdateJob < ApplicationJob
  def perform(product)
    product.account.etims_devices.active.where(id: Etims::ItemRegistration.where(product: product).select(:device_id)).each do |device|
      device.item_registrations.where(product: product).delete_all
      next unless device.initialized?

      begin
        device.register(product)
      rescue Etims::Client::Refused, JsonHttp::Unreachable => error
        Rails.logger.info "eTIMS item #{product.id} not registered again with #{device.name}: #{error.message}"
      end
    end
  end
end
