# Settings › Developers: owners manage API keys and webhooks.
module DeveloperSettings
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_manage_account
  end
end
