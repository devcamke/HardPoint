# Emails about a shop's subscription, to its owners.
class BillingMailer < ApplicationMailer
  helper CatalogueHelper

  def trial_ending
    @account = params[:account]
    mail to: @account.billing_recipients, subject: "Your HardPoint trial ends on #{@account.trial_ends_at.to_date.to_fs(:long)}"
  end

  def invoice_issued
    set_invoice
    mail_with_invoice "HardPoint invoice #{@invoice.number}: #{amount} due by #{@invoice.due_on.to_fs(:long)}"
  end

  def payment_reminder
    set_invoice
    mail_with_invoice "Reminder: #{amount} for HardPoint is due on #{@invoice.due_on.to_fs(:long)}"
  end

  def read_only
    set_invoice
    mail_with_invoice "#{@account.name} is read-only until the HardPoint invoice is paid"
  end

  def payment_received
    set_invoice
    @payment = params[:payment]
    mail_with_invoice "Thank you: HardPoint invoice #{@invoice.number} is paid"
  end

  private
    def set_invoice
      @invoice = params[:invoice]
      @account = @invoice.account
    end

    def amount
      Money.format(@invoice.amount_cents, currency: @invoice.currency)
    end

    def mail_with_invoice(subject)
      pdf = Billing::InvoicePdf.new(@invoice)
      attachments[pdf.filename] = { mime_type: "application/pdf", content: pdf.render }
      mail to: @account.billing_recipients, subject: subject
    end
end
