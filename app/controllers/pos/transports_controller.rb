# "Add transport" at the till: the trip to the customer's site as a line on the sale, at what it costs.
class Pos::TransportsController < ApplicationController
  include PosSale

  def create
    line = @sale.add_transport(amount_cents: (BigDecimal(params[:amount].to_s, exception: false).to_d * 100).round, destination: params[:destination])
    if line.persisted?
      render_cart message: "Added transport #{helpers.money(line.total_cents)}"
    else
      render_cart alert: line.errors.full_messages.to_sentence, status: :unprocessable_entity
    end
  end
end
