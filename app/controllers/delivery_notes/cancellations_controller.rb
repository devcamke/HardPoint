class DeliveryNotes::CancellationsController < ApplicationController
  include DeliveryNoteScoped

  def create
    if @delivery_note.cancel
      back_to_note notice: "Delivery cancelled."
    else
      back_to_note alert: "A delivered note can't be cancelled."
    end
  end
end
