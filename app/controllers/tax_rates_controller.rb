class TaxRatesController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name rate default ]
    end
end
