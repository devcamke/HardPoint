# Buy › From KRA: the invoices suppliers have issued to the shop's PIN, fetched from eTIMS, each waiting to be
# received into stock, recorded as an invoice, or set aside (Etims::Purchase).
class EtimsPurchasesController < ApplicationController
  before_action :ensure_can_purchase_or_pay

  def index
    @status = params[:status].presence_in(Etims::Purchase::STATUSES + %w[ all ]) || "new"
    purchases = visible_purchases.chronologically.includes(:supplier, :goods_receipt, :supplier_invoice, device: :branch)
    @counts = visible_purchases.group(:status).count
    purchases = purchases.where(status: @status) unless @status == "all"
    @purchases = paginate(purchases)
    @devices = within_visible_branches(Current.account.etims_devices.active).includes(:branch).select(&:initialized?)
  end

  def show
    @purchase = visible_purchases.find(params[:id])
    @suggested = @purchase.new? ? @purchase.suggested_products : {}
    @open_receipts = @purchase.supplier ? @purchase.supplier.goods_receipts.where.missing(:supplier_invoices).chronologically.limit(20) : []
  end

  private
    # A control unit belongs to a branch, and so do the invoices it fetched.
    def visible_purchases
      Current.account.etims_purchases.where(device_id: within_visible_branches(Current.account.etims_devices).select(:id))
    end
end
