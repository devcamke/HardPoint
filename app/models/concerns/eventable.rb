module Eventable
  extend ActiveSupport::Concern

  UNTRACKED_ATTRIBUTES = %w[ created_at updated_at password_digest pin_digest approval_pin_digest failed_pin_attempts ].freeze

  included do
    has_many :events, as: :eventable
  end

  class_methods do
    # Records "created", "updated" (with the changed attributes) and "destroyed" events.
    def tracks_lifecycle(only: %i[ create update destroy ])
      only = Array(only)
      after_create { track_event "created" } if only.include?(:create)
      after_update { track_event "updated", changes: tracked_changes if tracked_changes.any? } if only.include?(:update)
      after_destroy { track_event "destroyed" } if only.include?(:destroy)
    end
  end

  def track_event(action, creator: Current.user, **particulars)
    Event.create! account: event_account, eventable: self, action: action, creator: creator,
      particulars: { name: event_name }.merge(particulars.compact)
  end

  private
    def event_account
      account
    end

    def event_name
      try(:name) || "#{model_name.human} #{id}"
    end

    def tracked_changes
      saved_changes.except(*UNTRACKED_ATTRIBUTES)
    end
end
