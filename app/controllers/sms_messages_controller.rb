class SmsMessagesController < ApplicationController
  before_action :ensure_can_manage_account

  def index
    @messages = paginate(Current.account.sms_messages.chronologically.includes(:sender))
  end
end
