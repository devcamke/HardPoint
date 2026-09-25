# The stock app for phones, at /m: looking products up, counting and receiving, scanning with the camera.
class Mobile::BaseController < ApplicationController
  helper_method :scanned
  layout -> { turbo_frame_request? ? "turbo_rails/frame" : "mobile" }

  private
    def scanned
      @scanned ||= ScannedCode.new(Current.account, params[:code])
    end

    # A quantity entered in packs ("3 boxes") becomes base units; the pack must be the product's.
    def entered_quantity(product)
      pack = params[:product_unit_id].presence && product.product_units.find(params[:product_unit_id])
      params[:quantity].to_d * (pack&.quantity || 1)
    end
end
