class BrandsController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name ]
    end
end
