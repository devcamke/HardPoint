class CategoriesController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name parent_id etims_class_code ]
    end
end
