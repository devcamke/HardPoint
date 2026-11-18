# The offcuts of a product cut to length, kept right by hand from the product's page: a piece that was on the rack
# before HardPoint kept track is added, one thrown away is scrapped (out of stock, as cutting waste), and one listed
# by mistake is taken off the list.
class Products::OffcutsController < ApplicationController
  before_action :ensure_can_manage_stock
  before_action { @product = Current.account.products.cut_to_length.find(params[:product_id]) }

  def create
    offcut = Offcut.record(product: @product, branch: visible_branches.find(params[:branch_id]), length: params[:length])

    if offcut.persisted?
      redirect_to @product, notice: "#{@product.length_words(offcut.length)} offcut added at #{offcut.branch.name}."
    else
      redirect_to @product, alert: offcut.errors.full_messages.to_sentence
    end
  end

  def destroy
    offcut = within_visible_branches(@product.offcuts).find(params[:id])

    if params[:scrap].present?
      # Out of stock by hand, so it counts towards the day's write-off limit. There's no PIN box beside each offcut:
      # past the limit, an owner or manager scraps it.
      write_off = StockWriteOff.new(product: @product, branch: offcut.branch, quantity: offcut.length, reason: "cutting_waste")
      approver = approver_for_action if write_off.needs_approval?
      return redirect_to(@product, alert: "#{write_off.approval_needed_message}. Ask an owner or manager to scrap it.", status: :see_other) if write_off.needs_approval? && approver.nil?

      offcut.scrap
      write_off.approved(approver) if approver
      redirect_to @product, notice: "#{@product.length_words(offcut.length)} offcut scrapped.", status: :see_other
    else
      offcut.destroy!
      redirect_to @product, notice: "#{@product.length_words(offcut.length)} is no longer listed as an offcut.", status: :see_other
    end
  end
end
