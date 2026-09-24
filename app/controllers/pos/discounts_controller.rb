# A discount on the whole sale, typed as an amount ("500") or a percentage ("10%").
class Pos::DiscountsController < ApplicationController
  include PosSale

  def update
    Sale.transaction do
      @sale.update!(discount_cents: discount_cents)
      @sale.recalculate
      approve_discount!
    end
    render_cart message: @sale.discount_cents.zero? ? "Discount removed" : "Discount of #{Money.format(@sale.discount_cents)} applied"
  rescue ApprovalMissing => error
    render_cart alert: error.message, status: :unprocessable_entity
  end

  private
    def discount_cents
      raw = params[:discount].to_s.strip
      raw.end_with?("%") ? (@sale.subtotal_cents * raw.delete("%").to_d / 100).round : Monetary.to_cents(raw).to_i
    end
end
