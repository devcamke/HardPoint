# Stock to move between branches before ordering more: one branch is short of a product (at or below its reorder
# level, or the till turned customers away for it) while another holds more than it needs. Built on ReorderSuggestion,
# so "short" and "more than it needs" mean what the reorder list means by them, and a move never leaves the sending
# branch short in turn.
class BranchRebalancing
  REFUSALS_WITHIN = 14.days

  Move = Data.define(:product, :from_branch, :to_branch, :quantity, :reason) do
    def value_cents = (product.cost_cents * quantity).round
  end

  attr_reader :account

  def initialize(account)
    @account = account
  end

  # Every suggested move, the most valuable first.
  def moves
    @moves ||= branches.size < 2 ? [] : match
  end

  # Moves into one branch, grouped by the branch the stock comes from.
  def into(branch) = moves.select { _1.to_branch == branch }.group_by(&:from_branch)

  private
    def branches = @branches ||= account.branches.alphabetically.to_a

    def suggestions = @suggestions ||= branches.index_with { ReorderSuggestion.new(account, _1) }

    def match
      spare = Hash.new { |hash, key| hash[key] = suggestions.fetch(key.last).spare(key.first) }
      needs.sort_by { |need| -need[:quantity] * need[:product].cost_cents }.flat_map do |need|
        product, left = need[:product], need[:quantity]
        donors = branches.excluding(need[:branch]).sort_by { -spare[[ product, _1 ]] }
        donors.filter_map do |donor|
          available = spare[[ product, donor ]]
          next if left <= 0 || available <= 0

          quantity = [ left, available ].min
          spare[[ product, donor ]] -= quantity
          left -= quantity
          Move.new(product, donor, need[:branch], quantity, need[:reason])
        end
      end.sort_by { -_1.value_cents }
    end

    # What each branch is short of: the reorder list's shortfall, or for a product the till turned away and that's
    # now gone, the most a customer asked for.
    def needs
      branches.flat_map do |branch|
        short = suggestions[branch].rows.to_h { [ _1.product, { branch:, product: _1.product, quantity: _1.needed, reason: "at or below its reorder level" } ] }
        refused.fetch(branch.id, []).each do |product, times, wanted|
          on_hand = suggestions[branch].on_hand(product)
          gap = wanted - [ on_hand, 0 ].max
          next unless gap.positive?

          reason = "turned away #{times} #{"time".pluralize(times)} at the till"
          short[product] = short[product] ? short[product].merge(quantity: [ short[product][:quantity], gap ].max, reason: reason) : { branch:, product:, quantity: gap, reason: reason }
        end
        short.values
      end
    end

    # { branch id => [ [ product, times, largest quantity asked for ], … ] } over the last two weeks.
    def refused
      @refused ||= begin
        rows = account.stock_refusals.where(created_at: REFUSALS_WITHIN.ago..).group(:branch_id, :product_id)
          .pluck(:branch_id, :product_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(quantity)"))
        products = account.products.active.where(id: rows.map(&:second), track_stock: true, kit: false).includes(:unit, :supplier_products).index_by(&:id)
        rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(branch_id, product_id, times, wanted), by_branch|
          by_branch[branch_id] << [ products[product_id], times, wanted.to_d ] if products[product_id]
        end
      end
    end
end
