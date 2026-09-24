class DeliveryNotesController < ApplicationController
  before_action :ensure_can_sell
  before_action :set_delivery_note, only: :show

  def index
    notes = Current.account.delivery_notes.chronologically.includes(:branch, sale: :customer)
    @status = params[:status].presence_in(%w[ outstanding delivered cancelled all ]) || "outstanding"
    notes = case @status
    when "outstanding" then notes.outstanding
    when "all" then notes
    else notes.where(status: @status)
    end
    @delivery_notes = paginate(notes)
  end

  def show
    respond_to do |format|
      format.html
      format.pdf do
        pdf = DeliveryNotePdf.new(@delivery_note)
        send_data pdf.render, filename: pdf.filename, type: :pdf, disposition: :inline
      end
    end
  end

  def new
    @delivery_note = Current.account.delivery_notes.new(sale: Current.account.sales.completed.find(params[:sale_id]))
    @delivery_note.valid? # fills in the customer's address and phone
    @delivery_note.errors.clear
  end

  def create
    attributes = params.expect(delivery_note: %i[ sale_id address contact_phone note ])
    sale = Current.account.sales.find(attributes.delete(:sale_id))
    @delivery_note = Current.account.delivery_notes.new(attributes.merge(sale: sale))

    if @delivery_note.save
      redirect_to @delivery_note, notice: "Delivery note #{@delivery_note.reference} created. Print it to go with the goods."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_delivery_note
      @delivery_note = Current.account.delivery_notes.find(params[:id])
    end
end
