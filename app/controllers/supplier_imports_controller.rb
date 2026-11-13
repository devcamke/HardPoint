# Bringing suppliers and what the shop owes them across from a spreadsheet (SupplierImport). It sets debts, so
# it's the owner's to do.
class SupplierImportsController < ApplicationController
  include SpreadsheetUpload

  before_action :ensure_can_manage_account

  def new
    @import = SupplierImport.new(account: Current.account)
  end

  def create
    @import = import_from(SupplierImport, params.dig(:supplier_import, :file))
    @import.save ? render(:show) : render(:new, status: :unprocessable_entity)
  end
end
