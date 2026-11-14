# "Check KRA now": asks for new invoices straight away rather than waiting for the morning's run.
class EtimsPurchases::ChecksController < ApplicationController
  before_action :ensure_can_purchase_or_pay

  def create
    devices = within_visible_branches(Current.account.etims_devices.active).select(&:initialized?)
    added = devices.sum { Etims::Purchase.fetch(_1) }
    failed = devices.select { _1.purchases_error.present? }

    if failed.any?
      redirect_to etims_purchases_path, alert: "KRA didn't answer for #{failed.map { _1.branch.name }.to_sentence}: #{failed.first.purchases_error}", status: :see_other
    else
      redirect_to etims_purchases_path, notice: added.zero? ? "Nothing new from KRA." : "#{helpers.pluralize(added, "new invoice")} from KRA.", status: :see_other
    end
  end
end
