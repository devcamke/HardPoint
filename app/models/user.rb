class User < ApplicationRecord
  include Eventable, TwoFactor

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :accounts, through: :memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  MINIMUM_PASSWORD_LENGTH = 10

  validates :name, presence: true
  # Every way of setting a password (sign-up, an invitation, a reset, My profile) needs at least this many characters.
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # The link sent at sign-up. It stops working once the address is confirmed or changed.
  generates_token_for :email_confirmation, expires_in: 7.days do
    [ email_address, email_confirmed_at ]
  end

  def email_confirmed?
    email_confirmed_at.present?
  end

  def confirm_email
    update_column(:email_confirmed_at, Time.current) unless email_confirmed?
  end

  # A login made at sign-up for an address nobody has shown is theirs. When a shop adds that address, the person
  # who really has it chooses the password (from the invitation), and whoever made the login is signed out of it.
  def take_back_unconfirmed_login
    return if email_confirmed?

    Account.without_isolation { sessions.destroy_all }
    update!(password: SecureRandom.base58(32))
  end

  private
    # Users span shops, so their events are recorded in the shop they're acting in.
    def event_account
      Current.account
    end
end
