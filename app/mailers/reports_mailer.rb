# The owner's regular emails: yesterday's figures each morning, and the week just gone each Monday.
class ReportsMailer < ApplicationMailer
  helper CatalogueHelper, MailChartsHelper

  def daily_summary
    @account = params[:account]
    @date = params[:date]

    Time.use_zone(@account.time_zone) do
      @summary = OwnerSummary::Daily.new(@account, @date)
      mail to: @account.daily_summary_recipients,
        subject: "#{@account.name}: #{Money.format(@summary.totals[:takings], currency: @account.currency)} taken on #{@date.strftime("%A %-d %B")}"
    end
  end

  def weekly_summary
    @account = params[:account]
    @ends_on = params[:ends_on]

    Time.use_zone(@account.time_zone) do
      @summary = OwnerSummary::Weekly.new(@account, @ends_on)
      mail to: @account.weekly_summary_recipients,
        subject: "#{@account.name}: your week to #{@ends_on.strftime("%A %-d %B")}, #{Money.format(@summary.totals[:takings], currency: @account.currency)} taken"
    end
  end
end
