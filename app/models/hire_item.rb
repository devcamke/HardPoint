# A tool the shop hires out: one physical item with its asset tag (MIX-01, MIX-02…), where it's kept,
# what it costs a day (and a week, if the shop offers a weekly rate) and the deposit it needs.
class HireItem < ApplicationRecord
  include AccountOwned, Eventable, Monetary
  tracks_lifecycle

  STATUSES = %w[ available on_hire maintenance retired ].freeze

  belongs_to :branch
  has_many :hire_lines, dependent: :restrict_with_error

  enum :status, STATUSES.index_by(&:itself), default: "available"

  money_attribute :daily_rate, :weekly_rate, :deposit

  normalizes :asset_tag, with: ->(tag) { tag.strip.upcase }
  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 100 }
  validates :asset_tag, presence: true, length: { maximum: 30 }, uniqueness: { scope: :account_id }
  validates :daily_rate_cents, numericality: { greater_than: 0 }
  validates :weekly_rate_cents, numericality: { greater_than: 0 }, allow_nil: true
  validates :deposit_cents, numericality: { greater_than_or_equal_to: 0 }
  validates_same_account :branch

  scope :alphabetically, -> { order(:name, :asset_tag) }

  def label
    "#{name} #{asset_tag}"
  end
  alias_method :event_name, :label

  def earned_cents(since: 90.days.ago)
    hire_lines.where(returned_at: since..).sum("hire_lines.charge_cents + hire_lines.damage_cents")
  end
end
