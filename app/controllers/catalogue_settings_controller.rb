# Shared behaviour for the small lists that shape the catalogue: categories, brands, units,
# tax rates and price lists. Each subclass names its attributes; its views supply _fields and
# _columns partials, and the rest comes from app/views/catalogue_settings.
class CatalogueSettingsController < ApplicationController
  before_action :ensure_can_manage_catalogue, except: :index
  before_action :set_record, only: %i[ edit update destroy ]

  helper_method :resource_title

  def index
    @records = collection.alphabetically
    @record = collection.new
  end

  def create
    @record = collection.new(record_params)

    if @record.save
      redirect_to({ action: :index }, notice: "#{resource_title.singularize} added.")
    else
      @records = collection.alphabetically
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @record.update(record_params)
      redirect_to({ action: :index }, notice: "#{resource_title.singularize} updated.")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @record.destroy
      redirect_to({ action: :index }, notice: "#{resource_title.singularize} removed.", status: :see_other)
    else
      redirect_to({ action: :index }, alert: @record.errors.full_messages.to_sentence, status: :see_other)
    end
  end

  private
    def collection
      Current.account.public_send(controller_name)
    end

    def set_record
      @record = collection.find(params[:id])
    end

    def record_params
      params.expect(controller_name.singularize.to_sym => permitted_attributes)
    end

    def resource_title
      controller_name.humanize
    end
end
