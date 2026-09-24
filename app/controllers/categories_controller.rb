class CategoriesController < CatalogueSettingsController
  private
    def permitted_attributes
      %i[ name parent_id ]
    end
end
