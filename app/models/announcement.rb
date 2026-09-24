# A message from HardPoint to every shop, shown as a banner between its start and end.
class Announcement < ApplicationRecord
  LEVELS = %w[ info warning ].freeze

  validates :title, presence: true, length: { maximum: 150 }
  validates :level, inclusion: { in: LEVELS }
  validates :starts_at, presence: true
  validate :ends_after_start

  scope :current, -> { where(starts_at: ..Time.current).where("ends_at IS NULL OR ends_at > ?", Time.current).order(starts_at: :desc) }
  scope :chronologically, -> { order(starts_at: :desc) }

  def current?
    starts_at <= Time.current && (ends_at.nil? || ends_at > Time.current)
  end

  private
    def ends_after_start
      errors.add :ends_at, "must be after the start" if starts_at && ends_at && ends_at <= starts_at
    end
end
