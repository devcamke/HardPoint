# Proof of delivery: who received the goods, and a photo of the signed note.
class DeliveryNotes::DeliveriesController < ApplicationController
  include DeliveryNoteScoped

  def create
    if @delivery_note.deliver(received_by: params[:received_by], proof_photo: params[:proof_photo])
      back_to_note notice: "Delivered to #{@delivery_note.received_by}."
    else
      back_to_note alert: @delivery_note.errors.full_messages.to_sentence.presence || "Only a dispatched delivery can be marked delivered."
    end
  end
end
