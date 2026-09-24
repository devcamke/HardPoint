class AccountExportJob < ApplicationJob
  queue_as :default

  def perform(export)
    export.build
  end
end
