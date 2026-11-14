# A till: the point where sales are rung up, with how it prints receipts and opens its drawer.
class Register < ApplicationRecord
  include Eventable, CountsTowardsPlan
  counts_towards_plan :registers, counting: :active
  tracks_lifecycle

  belongs_to :account, default: -> { Current.account }
  belongs_to :branch
  has_many :shifts, dependent: :restrict_with_error

  def open_shift
    shifts.open.first
  end

  PRINT_MODES = %w[ browser qz_tray ].freeze
  RECEIPT_WIDTHS = [ 32, 42, 48 ].freeze

  # A weighing scale on the till computer's serial port, read by the browser (app/javascript/scale). Most scales send
  # the weight all the time; some wait to be asked, each maker with its own command.
  SCALE_MODES = {
    "none" => "No scale",
    "continuous" => "Sends the weight all the time (most scales)",
    "request_w" => "Answers W (Toledo 8217, CAS and compatibles)",
    "request_s" => "Answers S (Mettler Toledo SICS)",
    "request_q" => "Answers Q (A&D)",
    "request_p" => "Answers P (Ohaus)"
  }.freeze
  SCALE_BAUD_RATES = [ 1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200 ].freeze
  SCALE_FRAMINGS = { "8N1" => "8 data bits, no parity (most scales)", "7E1" => "7 data bits, even parity", "7O1" => "7 data bits, odd parity" }.freeze

  validates :scale_mode, inclusion: { in: SCALE_MODES.keys }
  validates :scale_baud_rate, inclusion: { in: SCALE_BAUD_RATES }
  validates :scale_framing, inclusion: { in: SCALE_FRAMINGS.keys }

  def scale?
    scale_mode != "none"
  end

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
