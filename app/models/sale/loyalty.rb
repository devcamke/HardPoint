# Points on a sale to a named customer: earned when it completes (on what wasn't paid with points),
# spent through the points tender, and handed back or taken back when it's voided or returned.
module Sale::Loyalty
  extend ActiveSupport::Concern

  included do
    has_many :loyalty_entries, dependent: :restrict_with_error

    after_update :earn_points, if: -> { saved_change_to_status? && completed? }
    after_update :reverse_points, if: -> { saved_change_to_status? && voided? }
  end

  def loyalty_program
    program = account.loyalty_program
    program if program&.enabled? && customer
  end

  def points_earned
    loyalty_entries.select { _1.kind == "earned" }.sum(&:points)
  end

  private
    def earn_points
      return unless (program = loyalty_program)

      earnable = total_cents - payments.select(&:points?).sum(&:amount_cents)
      points = program.points_for(earnable)
      loyalty_entries.create!(account: account, customer: customer, kind: "earned", points: points, creator: cashier) if points.positive?
    end

    # Earned points come off; points spent on it go back.
    def reverse_points
      net = loyalty_entries.sum(:points)
      loyalty_entries.create!(account: account, customer: customer, kind: "reversed", points: -net, creator: voided_by) if customer && net.nonzero?
    end
end
