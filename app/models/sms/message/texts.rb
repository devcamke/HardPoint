# What the texts say. Kept short: one SMS part (160 characters) where the numbers allow.
module Sms::Message::Texts
  extend ActiveSupport::Concern

  class_methods do
    def receipt(sale, to:)
      paid = sale.payments.map(&:label).uniq.to_sentence
      compose to: to, purpose: "receipt", source: sale,
        body: "#{sale.account.name}: receipt #{sale.receipt_number}, #{I18n.l(sale.completed_at, format: :short)}. " \
              "Total #{Money.format(sale.total_cents)} paid by #{paid.downcase}. Thank you!"
    end

    def order_ready(order)
      compose to: order.customer.phone, purpose: "order_ready", source: order,
        body: "#{order.account.name}: your order #{order.reference} is ready to collect at #{order.branch.name}. " \
              "#{"To pay: #{Money.format(order.balance_to_pay_cents)}. " if order.balance_to_pay_cents.positive?}Please bring the order number."
    end

    def balance_reminder(customer)
      paybill = customer.account.mpesa_shortcodes.for_branch(nil)
      overdue = customer.overdue_cents
      compose to: customer.phone, purpose: "balance_reminder", source: customer,
        body: "#{customer.account.name}: your account balance is #{Money.format(customer.balance_cents)}" \
              "#{", #{Money.format(overdue)} overdue" if overdue.positive?}. " \
              "#{"Pay to #{paybill.label}, account #{PhoneNumber.display(customer.phone).delete(" ")}. " if paybill}Thank you."
    end
  end
end
