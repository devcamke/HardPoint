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

  private
    # Users span shops, so their events are recorded in the shop they're acting in.
    def event_account
      Current.account
    end
end
