class ReportsMailer < ApplicationMailer
  helper CatalogueHelper

  def daily_summary
    @account = params[:account]
    @date = params[:date]

    Time.use_zone(@account.time_zone) do
      @dashboard = Dashboard.new(@account, date: @date)
      @totals = @dashboard.totals
      @payments = Report::Payments.new(account: @account, period: Report::Period.new(from: @date, to: @date)).sections.first.totals
      @shifts = Report::Shifts.new(account: @account, period: Report::Period.new(from: @date, to: @date)).sections.first.rows
      @voids = @account.sales.voided.where(voided_at: @date.all_day).count

      mail to: @account.daily_summary_recipients,
        subject: "#{@account.name}: #{Money.format(@totals[:takings], currency: @account.currency)} taken on #{@date.strftime("%A %-d %B")}"
    end
  end
end
