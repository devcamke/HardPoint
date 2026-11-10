class DeliveryNotes::CancellationsController < ApplicationController
  include DeliveryNoteScoped

  def create
    if @delivery_note.cancel
      back_to_note notice: "Delivery cancelled.#{" The transport order #{@delivery_note.transport_order.reference} was cancelled with it." if @delivery_note.transport_order&.cancelled?}"
    else
      back_to_note alert: @delivery_note.errors.full_messages.to_sentence.presence || "A delivered note can't be cancelled."
    end
  end
end
