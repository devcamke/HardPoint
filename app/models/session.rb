class Session < ApplicationRecord
  include Eventable

  IMPERSONATION_DURATION = 1.hour

  belongs_to :account, default: -> { Current.account }
  belongs_to :user
  belongs_to :impersonator, class_name: "User", optional: true

  enum :sign_in_method, %w[ password pin impersonation ].index_by(&:itself), prefix: :signed_in_with

  before_create { self.expires_at ||= IMPERSONATION_DURATION.from_now if signed_in_with_impersonation? }
  after_create :track_sign_in

  def membership
    @membership ||= account.memberships.find_by(user: user)
  end

  def impersonated?
    impersonator_id.present?
  end

  def expired?
    expires_at&.past?
  end

  private
    def event_name
      user.name
    end

    def track_sign_in
      case sign_in_method
      when "pin" then track_event "switched_in", creator: user
      when "impersonation" then track_event "impersonation_started", creator: user, administrator: impersonator.name
      else track_event "signed_in", creator: user, ip_address: ip_address
      end
    end
end
