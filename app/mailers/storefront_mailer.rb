# Emails about online store orders: to the shop's owners and managers, and to the customer.
class StorefrontMailer < ApplicationMailer
  helper CatalogueHelper

  def new_order
    set_order
    recipients = @account.users.where(memberships: { role: %w[ owner manager ] }).pluck(:email_address)
    mail to: recipients, subject: "New online order #{@order.reference}: #{Money.format(@order.total_cents)} from #{@order.customer.name}"
  end

  def confirmation
    set_order
    mail to: @order.customer.email, reply_to: @account.users.where(memberships: { role: "owner" }).pick(:email_address),
      subject: "#{@account.name}: your order #{@order.reference}"
  end

  private
    def set_order
      @order = params[:order]
      @account = @order.account
    end
end
