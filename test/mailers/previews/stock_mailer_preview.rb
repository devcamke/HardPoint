# Preview at http://demo.localhost:3000/rails/mailers/stock_mailer/low_stock_digest
class StockMailerPreview < ActionMailer::Preview
  def low_stock_digest
    account = Account.first
    Current.account = account
    StockMailer.with(account: account).low_stock_digest
  end
end
