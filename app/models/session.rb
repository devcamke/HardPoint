class Session < ApplicationRecord
  belongs_to :account, default: -> { Current.account }
  belongs_to :user

  def membership
    @membership ||= account.memberships.find_by(user: user)
  end
end
