# Preview at http://demo.localhost:3000/rails/mailers/supplier_returns_mailer/debit_note
class SupplierReturnsMailerPreview < ActionMailer::Preview
  def debit_note
    account = Account.first
    Current.account = account
    SupplierReturnsMailer.with(supplier_return: account.supplier_returns.last).debit_note
  end
end
