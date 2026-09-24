class ProductImports::RunsController < ApplicationController
  before_action :ensure_can_manage_catalogue

  def create
    import = Current.account.product_imports.find(params[:product_import_id])

    if import.run_later
      redirect_to import, notice: "Importing… this page updates when it's done.", status: :see_other
    else
      redirect_to import, alert: "This import can't be run.", status: :see_other
    end
  end
end
