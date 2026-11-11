# Stock › Labels: products waiting for a new shelf label (Product::Labelling), printed through the usual label sheets
# (LabelsController) and then marked done.
class LabelQueuesController < ApplicationController
  MAX_PRODUCTS = LabelsController::MAX_PRODUCTS

  before_action(only: :update) { head :forbidden unless current_membership&.can_manage_stock? }

  def show
    @products = Current.account.products.labels_due.includes(:barcodes, :unit).limit(MAX_PRODUCTS)
    @waiting = Current.account.products.labels_due.count
  end

  # The labels for these products are on the shelf now.
  def update
    ids = Array(params[:product_ids])
    done = Current.account.products.where(id: ids).labels_printed
    redirect_to label_queue_path, notice: "#{helpers.pluralize(done, "label")} marked as on the shelf.", status: :see_other
  end
end
