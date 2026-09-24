module Account::LowStockDigest
  extend ActiveSupport::Concern

  DIGEST_ROLES = %w[ owner manager stock_clerk ].freeze
  DIGEST_LIMIT = 50

  class_methods do
    # Called by LowStockDigestJob each morning, once for every shop.
    def send_low_stock_digests
      find_each do |account|
        Current.set(account: account) { account.send_low_stock_digest }
      end
    end
  end

  # Branch → products at or below their reorder level; branches with nothing low are left out.
  def low_stock_by_branch(limit: DIGEST_LIMIT)
    branches.alphabetically.to_h do |branch|
      [ branch, products.active.below_reorder_level_at(branch).includes(:unit)
          .select("products.*, COALESCE(stock_levels.quantity, 0) AS stock_quantity")
          .order(Arel.sql("COALESCE(stock_levels.quantity, 0) - products.reorder_level")).limit(limit).to_a ]
    end.reject { |_, products| products.empty? }
  end

  def low_stock_digest_recipients
    users.where(memberships: { role: DIGEST_ROLES }).pluck(:email_address)
  end

  def send_low_stock_digest
    if low_stock_by_branch(limit: 1).any? && low_stock_digest_recipients.any?
      StockMailer.with(account: self).low_stock_digest.deliver_later
    end
  end
end
