class DeliveryNotes::DispatchesController < ApplicationController
  include DeliveryNoteScoped

  def create
    if @delivery_note.dispatch(driver_name: params[:driver_name], vehicle: params[:vehicle].presence)
      back_to_note notice: "Dispatched with #{@delivery_note.driver_name}."
    else
      back_to_note alert: @delivery_note.errors.full_messages.to_sentence.presence || "Only a pending delivery can be dispatched."
    end
  end
end
