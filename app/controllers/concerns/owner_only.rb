# Exporting and closing the shop: owners only, and open while the shop is read-only or closing.
module OwnerOnly
  extend ActiveSupport::Concern

  included do
    allow_while_locked
    before_action { head :forbidden unless current_membership&.owner? }
  end
end
