# Mix-and-match bundles across a sale's lines, worked out again whenever the cart changes. Lines
# first get their own best promotion (SaleLine#apply_best_promotion); then each bundle running
# here, oldest first, takes the lines it covers if it saves more than their own promotions do.
# A line is in one promotion at most. Packs, lines with a hand discount and lines from customer
# orders stay out of bundles, and sales recorded from the offline till keep what the till worked out.
module Sale::Bundles
  extend ActiveSupport::Concern

  def apply_bundles
    return unless open? && offline_uuid.nil?

    lines.each { _1.apply_best_promotion if _1.promotion&.bundle? }
    claimed = []
    running_promotions.select(&:bundle?).sort_by(&:id).each do |promotion|
      shares = promotion.bundle_savings(lines.select { _1.bundleable? && !claimed.include?(_1) })
      next unless shares.any? && shares.values.sum > shares.keys.sum { _1.promotion_discount_cents.to_i }

      shares.each { |line, cents| line.promotion, line.promotion_discount_cents = promotion, cents }
      claimed.concat(shares.keys)
    end
    lines.each { _1.save! if _1.changed? }
  end
end
