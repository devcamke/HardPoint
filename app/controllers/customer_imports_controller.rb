# Bringing customers and what they owe across from a spreadsheet (CustomerImport). It sets debts, so it's the
# owner's to do.
class CustomerImportsController < ApplicationController
  include SpreadsheetUpload

  before_action :ensure_can_manage_account

  def new
    @import = CustomerImport.new(account: Current.account)
  end

  def create
    @import = import_from(CustomerImport, params.dig(:customer_import, :file))
    @import.save ? render(:show) : render(:new, status: :unprocessable_entity)
  end
end
