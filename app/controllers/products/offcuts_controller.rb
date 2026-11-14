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
      offcut.scrap
      redirect_to @product, notice: "#{@product.length_words(offcut.length)} offcut scrapped.", status: :see_other
    else
      offcut.destroy!
      redirect_to @product, notice: "#{@product.length_words(offcut.length)} is no longer listed as an offcut.", status: :see_other
    end
  end
end
