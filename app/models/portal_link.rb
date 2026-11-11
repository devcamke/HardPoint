# A customer's own page at the shop, opened from a link without signing in: what they owe and what's overdue, their
# open invoices and quotes, recent payments, a statement to download, and "Pay with M-Pesa" for the balance. Sent by
# WhatsApp or SMS so a contractor can settle up from site. The token is random and opens only this customer's page,
# at this shop, for 90 days unless it's taken back sooner.
class PortalLink < ApplicationRecord
  include AccountOwned, Eventable

  EXPIRES_IN = 90.days

  belongs_to :customer
  belongs_to :created_by, class_name: "User", default: -> { Current.user }, optional: true
  has_many :stk_requests, class_name: "Mpesa::StkRequest", dependent: :nullify

  has_secure_token :token, length: 32

  validates_same_account :customer
  before_validation(on: :create) { self.expires_at ||= EXPIRES_IN.from_now }

  scope :current, -> { where(revoked_at: nil).where(expires_at: Time.current..) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # The customer's current link, or a new one when there isn't one with at least a week to run, so a link sent
  # again is the same link.
  def self.for(customer)
    customer.portal_links.current.where(expires_at: 7.days.from_now..).newest_first.first ||
      create!(customer: customer).tap { _1.track_event "portal_link_created", customer: customer.name }
  end

  # The link a token stands for at this shop, counted as opened; nil if it's unknown, taken back, expired or
  # another shop's.
  def self.open(token, account)
    link = account.portal_links.current.find_by(token: token.to_s) or return
    link.update_columns(opened_count: link.opened_count + 1, last_opened_at: Time.current)
    link
  end

  def active? = revoked_at.nil? && expires_at.future?

  def revoke
    update!(revoked_at: Time.current)
    track_event "portal_link_revoked", customer: customer.name
  end

  def url
    Rails.application.routes.url_helpers.portal_url(token, subdomain: account.subdomain, **Rails.configuration.x.webhook_url_options)
  end

  # What goes in the WhatsApp or SMS message.
  def message
    balance = customer.balance_cents
    owed = balance.positive? ? " You owe #{Money.format(balance)}." : ""
    "#{account.name}: your account with us, with your invoices and statement#{", and pay with M-Pesa" if account.portal_payments?}.#{owed} #{url}"
  end
end
