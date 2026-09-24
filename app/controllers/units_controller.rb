class UnitsController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name abbreviation fractional etims_code ]
    end
end
