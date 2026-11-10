class SaleReturnsController < ApplicationController
  before_action :ensure_can_sell

  def index
    @returns = paginate(within_visible_branches(Current.account.sale_returns).chronologically.includes(:sale, :creator, :branch))
  end

  def show
    @return = within_visible_branches(Current.account.sale_returns).find(params[:id])
    respond_to do |format|
      format.html { render layout: "receipt" if params[:print] }
      format.pdf do
        pdf = CreditNotePdf.new(@return)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end
end
