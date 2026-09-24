class UnitsController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name abbreviation fractional ]
    end
end
