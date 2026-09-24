class Membership < ApplicationRecord
  belongs_to :account, default: -> { Current.account }
  belongs_to :user, autosave: true

  enum :role, %w[ owner manager cashier stock_clerk accountant ].index_by(&:itself), default: :cashier, validate: true

  validates :user, uniqueness: { scope: :account_id, message: "is already a member of this shop" }
  validate :account_keeps_an_owner, on: :update, if: -> { role_changed?(from: "owner") }

  before_destroy :ensure_not_last_owner

  scope :alphabetically, -> { joins(:user).order("users.name") }

  # Finds the person by email address, or creates a user with an unusable random password
  # that they replace through the invitation's set-password link.
  def user_attributes=(attributes)
    attributes = attributes.to_h.symbolize_keys
    email_address = attributes[:email_address].to_s.strip.downcase

    self.user = User.find_by(email_address: email_address) ||
      User.new(name: attributes[:name], email_address: email_address, password: SecureRandom.base58(32))
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

  def last_owner?
    role_in_database == "owner" && account.memberships.owner.excluding(self).none?
  end

  private
    def account_keeps_an_owner
      errors.add :role, "can't be changed: the shop needs at least one owner" if account.memberships.owner.excluding(self).none?
    end

    def ensure_not_last_owner
      if last_owner?
        errors.add :base, "The last owner can't be removed"
        throw :abort
      end
    end
end
