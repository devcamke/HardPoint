class Membership < ApplicationRecord
  include Eventable
  tracks_lifecycle only: %i[ update destroy ]
  after_create { track_event "created", role: role }

  belongs_to :account, default: -> { Current.account }
  belongs_to :user, autosave: true

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
  validate :account_keeps_an_owner, on: :update, if: -> { role_changed?(from: "owner") }

  before_destroy :ensure_not_last_owner

  scope :alphabetically, -> { joins(:user).order("users.name") }
  scope :with_pin, -> { where.not(pin_digest: nil).where(role: PIN_ROLES) }

  before_save :clear_pin, if: -> { role_changed? && !pin_role? }
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
    def account_keeps_an_owner
      errors.add :role, "can't be changed: the shop needs at least one owner" if account.memberships.owner.excluding(self).none?
    end

    def pin_only_for_till_roles
      errors.add :pin, "is only for cashiers and stock clerks" unless pin_role?
    end

    def clear_pin
      self.pin_digest = nil
    end

    def ensure_not_last_owner
      if last_owner?
        errors.add :base, "The last owner can't be removed"
        throw :abort
      end
    end
end
