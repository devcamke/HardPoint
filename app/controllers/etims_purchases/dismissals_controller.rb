# An invoice from KRA that isn't to be recorded here is set aside, and can be brought back.
class EtimsPurchases::DismissalsController < EtimsPurchases::BaseController
  before_action :ensure_can_purchase_or_pay

  def create
    if @purchase.dismiss(reason: params[:reason])
      redirect_to etims_purchases_path, notice: "#{@purchase.name} set aside.", status: :see_other
    else
      redirect_to @purchase, alert: "This invoice has already been #{@purchase.status}.", status: :see_other
    end
  end

  def destroy
    @purchase.restore
    redirect_to @purchase, notice: "Back among the invoices waiting.", status: :see_other
  end
end
