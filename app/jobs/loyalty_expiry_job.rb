# Points that have run out are expired, and customers whose points run out at the end of the month
# are warned by text.
class LoyaltyExpiryJob < ApplicationJob
  def perform
    LoyaltyProgram.expire_points
  end
end
