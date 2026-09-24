class StockMailer < ApplicationMailer
  helper CatalogueHelper

  def low_stock_digest
    @account = params[:account]
    @low_stock = @account.low_stock_by_branch
    count = @low_stock.values.sum(&:size)

    mail to: @account.low_stock_digest_recipients, subject: "#{@account.name}: #{count} #{"product".pluralize(count)} to reorder"
  end
end
