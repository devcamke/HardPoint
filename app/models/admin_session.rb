class AdminSession < ApplicationRecord
  DURATION = 12.hours

  belongs_to :user

  def expired?
    created_at < DURATION.ago
  end
end
