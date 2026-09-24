# A till: the point where sales are rung up, with how it prints receipts and opens its drawer.
class Register < ApplicationRecord
  include Eventable, CountsTowardsPlan
  counts_towards_plan :registers, counting: -> { active? }
  tracks_lifecycle

  belongs_to :account, default: -> { Current.account }
  belongs_to :branch
  has_many :shifts, dependent: :restrict_with_error

  def open_shift
    shifts.open.first
  end

  PRINT_MODES = %w[ browser qz_tray ].freeze
  RECEIPT_WIDTHS = [ 32, 42, 48 ].freeze

  validates :name, presence: true, uniqueness: { scope: :branch_id }
  validates :print_mode, inclusion: { in: PRINT_MODES }
  validates :receipt_width, inclusion: { in: RECEIPT_WIDTHS }
  validates :printer_name, presence: { message: "is needed to print through QZ Tray" }, if: -> { print_mode == "qz_tray" }
  validate :branch_belongs_to_account

  scope :active, -> { where(active: true) }
  scope :ordered, -> { includes(:branch).order("branches.name", :name) }

  private
    def branch_belongs_to_account
      errors.add :branch, "must be one of this shop's branches" if branch && branch.account_id != account_id
    end
end
