# An entry in a shop's audit trail: who did what, to which record, and when.
# Events are append-only; they outlive the records they describe, so each one keeps a
# snapshot of the record's name in its particulars.
class Event < ApplicationRecord
  belongs_to :account, default: -> { Current.account }
  belongs_to :creator, class_name: "User", optional: true
  belongs_to :eventable, polymorphic: true

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :before, ->(event) { where("(events.created_at, events.id) < (?, ?)", event.created_at, event.id) if event }

  def readonly?
    persisted?
  end
end
