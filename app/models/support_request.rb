# A question or problem sent to HardPoint support from inside a shop, with the page it came from.
class SupportRequest < ApplicationRecord
  belongs_to :account, default: -> { Current.account }
  belongs_to :user, default: -> { Current.user }

  enum :status, %w[ open resolved ].index_by(&:itself), default: "open"

  validates :subject, presence: true, length: { maximum: 150 }
  validates :body, presence: true, length: { maximum: 5_000 }
  validates :page, length: { maximum: 500 }

  scope :chronologically, -> { order(created_at: :desc) }

  after_create_commit -> { SupportMailer.with(support_request: self).received.deliver_later }

  def reference = "SR-#{id.to_s.rjust(5, "0")}"
end
