class Session < ApplicationRecord
  include Eventable

  IMPERSONATION_DURATION = 1.hour
  # A session ends by itself after two weeks without a request, and after three months whatever happens, so a
  # browser on a till that was replaced or a phone that was lost doesn't stay signed in for ever.
  IDLE_LIMIT = 14.days
  ABSOLUTE_LIMIT = 90.days
  # last_seen_at is written at most this often, so a busy till doesn't update its session on every scan.
  SEEN_EVERY = 1.hour

  belongs_to :account, default: -> { Current.account }
  belongs_to :user
  belongs_to :impersonator, class_name: "User", optional: true

  enum :sign_in_method, %w[ password pin impersonation google ].index_by(&:itself), prefix: :signed_in_with

  before_create { self.expires_at ||= IMPERSONATION_DURATION.from_now if signed_in_with_impersonation? }
  before_create { self.last_seen_at ||= Time.current }
  after_create :track_sign_in

  scope :newest_first, -> { order(last_seen_at: :desc, id: :desc) }
  scope :expired, -> { where(expires_at: ..Time.current).or(where(last_seen_at: ..IDLE_LIMIT.ago)).or(where(created_at: ..ABSOLUTE_LIMIT.ago)) }

  def membership
    @membership ||= account.memberships.find_by(user: user)
  end

  def impersonated?
    impersonator_id.present?
  end

  def expired?
    expires_at&.past? || last_seen_at < IDLE_LIMIT.ago || created_at < ABSOLUTE_LIMIT.ago
  end

  def seen
    update_column(:last_seen_at, Time.current) if last_seen_at < SEEN_EVERY.ago
  end

  # "Chrome on Windows", "Safari on iPhone": enough to recognise a device in the signed-in list, from the browser's user agent.
  def device
    agent = user_agent.to_s
    browser = case agent
    when /Edg\//i then "Edge"
    when /OPR\//, /Opera/ then "Opera"
    when /Firefox\//i then "Firefox"
    when /Chrome\//i then "Chrome"
    when /Safari\//i then "Safari"
    else "A browser"
    end
    system = case agent
    when /iPhone/i then "iPhone"
    when /iPad/i then "iPad"
    when /Android/i then "Android"
    when /Windows/i then "Windows"
    when /Mac OS X/i then "Mac"
    when /CrOS/i then "ChromeOS"
    when /Linux/i then "Linux"
    end
    system ? "#{browser} on #{system}" : browser
  end

  # Expired sessions are removed as they're used; this sweeps the ones nobody comes back to (nightly, across shops).
  def self.purge_expired
    expired.delete_all
  end

  private
    def event_name
      user.name
    end

    def track_sign_in
      case sign_in_method
      when "pin" then track_event "switched_in", creator: user
      when "impersonation" then track_event "impersonation_started", creator: user, administrator: impersonator.name
      when "google" then track_event "signed_in", creator: user, ip_address: ip_address, with: "Google"
      else track_event "signed_in", creator: user, ip_address: ip_address
      end
    end
end
