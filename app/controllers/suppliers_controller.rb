class SuppliersController < ApplicationController
  before_action :ensure_can_purchase_or_pay
  before_action :ensure_can_purchase, except: %i[ index show ]
  before_action :set_supplier, only: %i[ show edit update ]

  def index
    @suppliers = paginate(Current.account.suppliers.search(params[:query]).alphabetically)
  end

  def show
    @supplier_products = @supplier.supplier_products.includes(product: :unit).joins(:product).order("products.name")
    @purchase_orders = @supplier.purchase_orders.chronologically.includes(:branch).limit(10)
    @open_invoices = @supplier.open_invoices
    @payments = @supplier.supplier_payments.chronologically.limit(10)
  end

  def new
    @supplier = Current.account.suppliers.new
  end

  def create
    @supplier = Current.account.suppliers.new(supplier_params)

    if @supplier.save
      redirect_to @supplier, notice: "#{@supplier.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to @supplier, notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_supplier
      @supplier = Current.account.suppliers.find(params[:id])
    end

    def supplier_params
      params.expect(supplier: %i[ name contact_name phone email tax_pin address payment_terms_days currency active notes ])
    end
end
