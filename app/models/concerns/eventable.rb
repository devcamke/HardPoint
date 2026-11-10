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

  # An `approver:` given as a User is kept by name, and flagged when it's the person who did the thing.
  # While HardPoint support is signed in as someone, what's done is theirs in name only: the support
  # person is kept too, so Activity shows who really did it.
  def track_event(action, creator: Current.user, **particulars)
    if (approver = particulars[:approver]).is_a?(User)
      particulars.merge!(approver: approver.name, self_approved: (true if approver == creator))
    end

    Event.create! account: event_account, eventable: self, action: action, creator: creator,
      particulars: { name: event_name, api_key: Current.api_key&.name, impersonated_by: impersonator_name }.merge(particulars).compact
  end

  private
    def impersonator_name
      Current.session.impersonator&.name if Current.session&.impersonated?
    end

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
