class ProductImportRunJob < ApplicationJob
  queue_as :default

  def perform(import)
    import.run
  end
end
