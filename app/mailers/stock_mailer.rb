class StockMailer < ApplicationMailer
  helper CatalogueHelper, MailChartsHelper

  def low_stock_digest
    @account = params[:account]
    @low_stock = @account.low_stock_by_branch
    @out_of_stock = @account.out_of_stock_unwatched_by_branch
    count = @low_stock.values.sum(&:size) + @out_of_stock.values.sum(&:size)

    mail to: @account.low_stock_digest_recipients, subject: "#{@account.name}: #{count} #{"product".pluralize(count)} to reorder"
  end
end
