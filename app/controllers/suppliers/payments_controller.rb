class Suppliers::PaymentsController < ApplicationController
  before_action :ensure_can_manage_payables, :set_supplier

  def new
    @payment = @supplier.supplier_payments.new(paid_on: Date.current, amount_cents: [ @supplier.balance_cents, 0 ].max)
  end

  def create
    @payment = @supplier.supplier_payments.new(params.expect(supplier_payment: %i[ paid_on amount payment_method reference note ]).merge(account: Current.account))

    if @payment.save
      redirect_to @supplier, notice: "Payment of #{Money.format(@payment.amount_cents)} recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def set_supplier
      @supplier = Current.account.suppliers.find(params[:supplier_id])
    end
end
