# Tells the shop's webhook endpoints about a change, once it's committed.
module PublishesWebhooks
  extend ActiveSupport::Concern

  class_methods do
    # publishes_webhooks "product", updated: -> { price_cents changed… } — created and updated events,
    # the update one only when `updated` says the change is worth telling.
    def publishes_webhooks(name, updated: -> { saved_changes.except("updated_at").any? })
      after_create_commit { publish_webhook "#{name}.created" }
      after_update_commit { publish_webhook "#{name}.updated" if instance_exec(&updated) }
    end
  end

  private
    def publish_webhook(event)
      WebhookEndpoint.publish(account, event, self)
    end
end
