class User < ApplicationRecord
  include Eventable, TwoFactor

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :accounts, through: :memberships

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  private
    # Users span shops, so their events are recorded in the shop they're acting in.
    def event_account
      Current.account
    end
end
