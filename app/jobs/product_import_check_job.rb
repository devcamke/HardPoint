class ProductImportCheckJob < ApplicationJob
  queue_as :default

  def perform(import)
    import.check
  end
end
