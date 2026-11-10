class Membership < ApplicationRecord
  include Eventable, CountsTowardsPlan
  counts_towards_plan :users
  tracks_lifecycle only: %i[ update destroy ]
  after_create { track_event "created", role: role }

  belongs_to :account, default: -> { Current.account }
  belongs_to :user, autosave: true
  # Set, the member sees and works at this branch only. Owners see every branch.
  belongs_to :branch, optional: true

  PIN_ROLES = %w[ cashier stock_clerk ].freeze
  PIN_ATTEMPTS_ALLOWED = 5

  enum :role, %w[ owner manager cashier stock_clerk accountant ].index_by(&:itself), default: :cashier, validate: true

  # A short PIN lets staff switch in at a shared till that's already signed in. It's limited
  # to roles without admin rights, so it can never stand in for an owner's password and 2FA.
  has_secure_password :pin, validations: false
  has_secure_password :approval_pin, validations: false

  validates :pin, format: { with: /\A\d{4,6}\z/, message: "must be 4 to 6 digits" }, allow_nil: true
  validate :pin_only_for_till_roles, if: -> { pin.present? }
  validates :approval_pin, format: { with: /\A\d{4,6}\z/, message: "must be 4 to 6 digits" }, allow_nil: true
  validate { errors.add :approval_pin, "is only for owners and managers" if approval_pin.present? && !approver? }

  validates :user, uniqueness: { scope: :account_id, message: "is already a member of this shop" }
  validate { errors.add :branch, "must be one of this shop's" if branch && branch.account_id != account_id }
  validate { errors.add :branch, "can't be set for an owner: owners see every branch" if owner? && branch }
  validate :account_keeps_an_owner, on: :update, if: -> { role_changed?(from: "owner") }

  before_destroy :ensure_not_last_owner
  # Someone who no longer works here is signed out of every device at once, not on their next click, and
  # HardPoint support signed in as them is signed out too.
  after_destroy { account.sessions.where(user_id: user_id).destroy_all }

  scope :alphabetically, -> { joins(:user).order("users.name") }
  scope :with_pin, -> { where.not(pin_digest: nil).where(role: PIN_ROLES) }

  before_save :clear_pin, if: -> { role_changed? && !pin_role? }
  before_validation { self.branch = nil if owner? && will_save_change_to_role? }
  before_save(if: -> { role_changed? && !approver? }) { self.approval_pin_digest = nil }

  # Finds the person by email address, or creates a user with an unusable random password
  # that they replace through the invitation's set-password link.
  def user_attributes=(attributes)
    attributes = attributes.to_h.symbolize_keys
    email_address = attributes[:email_address].to_s.strip.downcase

    self.user = User.find_by(email_address: email_address) ||
      User.new(name: attributes[:name], email_address: email_address, password: SecureRandom.base58(32))
  end

  def event_name
    user.name
  end

  # The branches this member may see: one, or all of them.
  def visible_branches
    branch ? account.branches.where(id: branch_id) : account.branches
  end

  def bound_to_branch?
    branch_id.present?
  end

  def sees_branch?(other)
    branch_id.nil? || other&.id == branch_id
  end

  def two_factor_required?
    (owner? || manager?) && account.require_two_factor_for_managers?
  end

  def can_manage_account?
    owner?
  end

  def can_manage_staff?
    owner? || manager?
  end

  def can_manage_branches?
    owner? || manager?
  end

  def can_manage_catalogue?
    owner? || manager? || stock_clerk?
  end

  def can_manage_stock?
    owner? || manager? || stock_clerk?
  end

  def can_purchase?
    owner? || manager? || stock_clerk?
  end

  # Supplier invoices and payments: the money side of purchasing.
  def can_manage_payables?
    owner? || manager? || accountant?
  end

  # Sales, margins, tax and the owner's dashboard.
  def can_view_reports?
    owner? || manager? || accountant?
  end

  # Who owes the shop: statements, ageing, and payments taken away from a till.
  def can_manage_receivables?
    owner? || manager? || accountant?
  end

  def can_approve_stock_counts?
    owner? || manager?
  end

  # Cashiers see selling prices but not what the shop paid.
  def can_see_costs?
    !cashier?
  end

  def approver?
    owner? || manager?
  end

  def can_sell?
    !accountant?
  end

  def set_approval_pin(pin)
    if pin.blank?
      errors.add :approval_pin, "can't be blank"
      false
    elsif update(approval_pin: pin)
      track_event "approval_pin_set"
    end
  end

  # A shop can reset two-factor only for someone whose sole shop it is: a person's sign-in is shared by every
  # shop they work for, so one shop mustn't weaken it for the others. HardPoint support can reset anyone's.
  def two_factor_resettable_by_shop?
    Account.without_isolation { user.memberships.count } == 1
  end

  # For someone who has lost their phone and their recovery codes. They're signed out everywhere, told by
  # email, and set two-factor up again on their next sign-in if the shop requires it.
  def reset_two_factor(administrator: nil)
    return false unless user.two_factor_enabled?

    user.disable_two_factor
    Account.without_isolation { user.sessions.destroy_all }
    track_event "two_factor_reset", administrator: administrator&.email_address
    MembershipsMailer.with(membership: self, by: administrator ? "HardPoint support" : Current.user&.name).two_factor_reset.deliver_later
    true
  end

  def pin_role?
    role.in?(PIN_ROLES)
  end

  def pin_locked?
    failed_pin_attempts >= PIN_ATTEMPTS_ALLOWED
  end

  def set_pin(pin)
    if pin.blank?
      errors.add :pin, "can't be blank"
      false
    elsif update(pin: pin, failed_pin_attempts: 0)
      track_event "pin_set"
    end
  end

  def remove_pin
    update! pin_digest: nil, failed_pin_attempts: 0
    track_event "pin_removed"
  end

  # Too many wrong guesses lock the PIN until its owner signs in with their password and sets a new one.
  def switch_in_with_pin(pin)
    return false if pin_locked? || !pin_digest?

    if authenticate_pin(pin)
      update_columns failed_pin_attempts: 0
      true
    else
      increment! :failed_pin_attempts
      false
    end
  end

  def last_owner?
    role_in_database == "owner" && account.memberships.owner.excluding(self).none?
  end

  private
    # Two owners removing or demoting each other at once would each see the other still there and both go
    # ahead, leaving no owner. Locking the shop's row first makes the second wait and then see the first.
    def lock_account
      Account.where(id: account_id).lock.pluck(:id)
    end

    def account_keeps_an_owner
      lock_account
      errors.add :role, "can't be changed: the shop needs at least one owner" if account.memberships.owner.excluding(self).none?
    end

    def pin_only_for_till_roles
      errors.add :pin, "is only for cashiers and stock clerks" unless pin_role?
    end

    def clear_pin
      self.pin_digest = nil
    end

    def ensure_not_last_owner
      lock_account if role_in_database == "owner"
      if last_owner?
        errors.add :base, "The last owner can't be removed"
        throw :abort
      end
    end
end
