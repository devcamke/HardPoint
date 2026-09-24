module DeliveryNoteScoped
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_sell, :set_delivery_note
  end

  private
    def set_delivery_note
      @delivery_note = Current.account.delivery_notes.find(params[:delivery_note_id])
    end

    def back_to_note(notice: nil, alert: nil)
      redirect_to @delivery_note, notice: notice, alert: alert || @delivery_note.errors.full_messages.to_sentence.presence, status: :see_other
    end
end
