# Sending a document or a balance reminder from HardPoint's WhatsApp number (create), and the messages a shop has
# sent with what became of each (index, under Settings).
class WhatsappMessagesController < ApplicationController
  include SharedDocument

  before_action :ensure_feature
  before_action :set_document, only: :create
  before_action :ensure_can_manage_account, only: :index

  def index
    @messages = paginate(Current.account.whatsapp_messages.newest_first.includes(:sent_by, :document))
  end

  def create
    phone = params[:phone].presence || @document.try(:customer)&.phone || @document.try(:phone)
    message = if params[:reminder].present? && @document.is_a?(Customer)
      Whatsapp::Message.deliver_balance_reminder(@document)
    else
      Whatsapp::Message.deliver_document(@document, phone: phone, name: @document.try(:customer)&.name || @document.try(:name), from: period(:from), to: period(:to))
    end

    if message.persisted?
      redirect_back_or_to root_path, notice: "Sending on WhatsApp to #{PhoneNumber.display(phone)}. Its page shows when it's delivered and read.", status: :see_other
    else
      redirect_back_or_to root_path, alert: "Not sent: #{message.errors.full_messages.to_sentence}.", status: :see_other
    end
  end

  private
    def ensure_feature
      head :not_found unless Current.account.feature?(:whatsapp_messages)
    end
end
