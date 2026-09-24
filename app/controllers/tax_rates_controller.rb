class TaxRatesController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name rate default etims_code ]
    end
end
