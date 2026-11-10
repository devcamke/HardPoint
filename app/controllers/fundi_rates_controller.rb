# The commission fundis earn: a shop-wide percentage, and a percentage per category for the ones that differ
# (cement earning less than fittings, say). A subcategory without a rate uses its parent's.
class FundiRatesController < ApplicationController
  before_action :ensure_approver

  def edit
    @categories = categories
  end

  def update
    shop_categories = categories
    rates = params.fetch(:categories, {}).permit(*shop_categories.map { _1.id.to_s }).to_h
    Account.transaction do
      Current.account.update!(fundi_commission_percent: params[:fundi_commission_percent].presence || 0)
      shop_categories.each do |category|
        next unless rates.key?(category.id.to_s)

        category.update!(fundi_commission_percent: rates[category.id.to_s].presence)
      end
    end
    redirect_to fundis_path, notice: "Commission rates saved."
  rescue ActiveRecord::RecordInvalid => invalid
    @categories = categories
    flash.now[:alert] = invalid.record.errors.full_messages.to_sentence
    render :edit, status: :unprocessable_entity
  end

  private
    def ensure_approver
      head :forbidden unless current_membership&.approver?
    end

    def categories
      Current.account.categories.includes(:parent).sort_by(&:full_name)
    end
end
