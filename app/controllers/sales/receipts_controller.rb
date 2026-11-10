class Sales::ReceiptsController < ApplicationController
  include SaleScoped

  def show
    respond_to do |format|
      format.html { render layout: "receipt" }
      format.json { render json: ReceiptData.new(@sale) }
      # The till-roll receipt as a PDF, to share or save as a picture.
      format.pdf do
        pdf = ReceiptPdf.new(@sale)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end
end
