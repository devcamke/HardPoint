# The few emails sent straight away rather than in the morning: see Account::OwnerAlerts for when.
class OwnerAlertsMailer < ApplicationMailer
  helper CatalogueHelper, MailChartsHelper

  def shift_short
    @shift = params[:record]
    @account = @shift.account
    in_shop_time do
      mail to: params[:recipients], subject: "#{@account.name}: #{@shift.register.name} closed #{Money.format(-@shift.variance_cents, currency: @account.currency)} short"
    end
  end

  def large_void
    @sale = params[:record]
    @account = @sale.account
    in_shop_time do
      mail to: params[:recipients], subject: "#{@account.name}: sale #{@sale.receipt_number} for #{Money.format(@sale.total_cents, currency: @account.currency)} was voided"
    end
  end

  def count_loss
    @count = params[:record]
    @account = @count.account
    in_shop_time do
      mail to: params[:recipients], subject: "#{@account.name}: a stock count at #{@count.branch.name} came out #{Money.format(-@count.variance_value_cents, currency: @account.currency)} short"
    end
  end

  private
    def in_shop_time(&) = Time.use_zone(@account.time_zone, &)
end
