class ProductImportsController < ApplicationController
  before_action :ensure_can_manage_catalogue

  def index
    @imports = paginate(Current.account.product_imports.chronologically.includes(:creator, :branch))
  end

  def new
    @import = Current.account.product_imports.new(branch: selected_branch)
  end

  def create
    file = params.dig(:product_import, :file)
    @import = Current.account.product_imports.new(
      filename: file.respond_to?(:original_filename) ? file.original_filename : nil,
      csv: read_csv(file),
      branch: params.dig(:product_import, :branch_id).presence && Current.account.branches.find(params.dig(:product_import, :branch_id)))

    if @import.save
      redirect_to @import
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @import = Current.account.product_imports.find(params[:id])
  end

  private
    # Spreadsheets saved from Excel are often Windows-1252 and start with a byte-order mark.
    def read_csv(file)
      return "" unless file.respond_to?(:read)
      return "x" * (ProductImport::MAX_SIZE + 1) if file.size > ProductImport::MAX_SIZE

      text = file.read.delete_prefix("\xEF\xBB\xBF".b)
      text.force_encoding(Encoding::UTF_8).valid_encoding? ? text : text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
    end
end
