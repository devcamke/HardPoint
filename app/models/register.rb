# A till: the point where sales are rung up. Receipt printers and cash drawers attach here later.
class Register < ApplicationRecord
  include Eventable
  tracks_lifecycle

  belongs_to :account, default: -> { Current.account }
  belongs_to :branch
  has_many :shifts, dependent: :restrict_with_error

  def open_shift
    shifts.open.first
  end

  validates :name, presence: true, uniqueness: { scope: :branch_id }
  validate :branch_belongs_to_account

  scope :active, -> { where(active: true) }
  scope :ordered, -> { includes(:branch).order("branches.name", :name) }

  private
    def branch_belongs_to_account
      errors.add :branch, "must be one of this shop's branches" if branch && branch.account_id != account_id
    end
end
