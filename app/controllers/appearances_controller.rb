# The shop's look: a colour theme (a preset or its own colour), its logo, and the receipt's stamp.
class AppearancesController < ApplicationController
  before_action :ensure_can_manage_account

  def edit
    @account = Current.account
  end

  def update
    @account = Current.account
    @account.theme_color = params[:theme] == "custom" ? params[:custom_color] : Theme::PRESETS[params[:theme]]&.color || @account.theme_color
    @account.receipt_stamp = params[:receipt_stamp] == "1"
    @account.logo.purge_later if params[:remove_logo] == "1" && @account.logo.attached?
    @account.logo.attach(params[:logo]) if params[:logo].present?

    if @account.save
      redirect_to edit_appearance_path, notice: "Saved. This is how HardPoint looks for everyone at #{@account.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
