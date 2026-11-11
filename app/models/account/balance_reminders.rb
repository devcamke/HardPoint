# Credit control's weekly reminders. Each Monday at 9 (Nairobi), shops that ask for it (Settings › Preferences,
# weekly_reminders) remind every customer with an overdue invoice of what they owe: by SMS (with the customer portal
# link when that's on), or on WhatsApp with their statement attached. Customers who've asked not to be texted, or
# have no phone number, aren't sent anything; SMS is still one reminder a day per customer and within the shop's
# daily limit (Sms::Message).
module Account::BalanceReminders
  extend ActiveSupport::Concern

  class_methods do
    # Called by WeeklyBalanceRemindersJob, once for every shop that sends them.
    def send_weekly_balance_reminders
      where("preferences ->> 'weekly_reminders' IN ('sms', 'whatsapp')").find_each do |account|
        Current.set(account: account) do
          Time.use_zone(account.time_zone) { account.send_balance_reminders }
        end
      end
    end
  end

  # Customers this shop's reminders would go to: owing, overdue, with a phone, not opted out.
  def customers_to_remind
    customers.with_balances(account: self).filter_map do |customer, balance|
      customer if balance.positive? && customer.phone.present? && !customer.sms_opt_out? && customer.overdue_cents.positive?
    end
  end

  # How many reminders went out.
  def send_balance_reminders
    case weekly_reminders
    when "sms"
      return 0 unless sms_enabled?

      customers_to_remind.count { Sms::Message.balance_reminder(_1).persisted? }
    when "whatsapp"
      return 0 unless feature?(:whatsapp_messages) && Whatsapp.available?

      customers_to_remind.count { Whatsapp::Message.deliver_balance_reminder(_1).persisted? }
    else
      0
    end
  end
end
