# Settings › Online store.
class StorefrontsController < ApplicationController
  before_action :ensure_can_manage_account
  before_action { @storefront = Storefront.for(Current.account) }

  def edit
  end

  def update
    if @storefront.update(storefront_params)
      redirect_to edit_storefront_path, notice: @storefront.enabled? ? "Online store saved. It's live at #{store_root_url}." : "Online store saved (switched off).", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def storefront_params
      params.expect(storefront: [ :enabled, :headline, :intro, :collection_note, :contact_phone, :show_stock_levels, collection_branch_ids: [] ])
    end
end
