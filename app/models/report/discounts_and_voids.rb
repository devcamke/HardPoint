# Where money was given away or taken back: discounts, voids and returns per cashier, every
# voided sale, and the biggest discounts with who approved them.
class Report::DiscountsAndVoids < Report
  self.title = "Discounts, voids and returns"
  self.description = "Per cashier, every voided sale, and the biggest discounts with their approvers"
  self.group = "Sales and money"

  def sections
    [ Section.new(title: "By cashier", columns: cashier_columns, rows: cashier_rows, totals: cashier_totals),
      Section.new(title: "Voided sales", columns: void_columns, rows: void_rows),
      Section.new(title: "Biggest discounts", columns: discount_columns, rows: discount_rows) ]
  end

  private
    def voided_sales
      scope = account.sales.voided.where(voided_at: period.range)
      branch ? scope.where(branch: branch) : scope
    end

    def cashier_columns
      [ Column.new("Cashier", :text), Column.new("Sales", :count), Column.new("Discounts given", :money), Column.new("Sales discounted", :count),
        Column.new("Voids", :count), Column.new("Voided value", :money), Column.new("Returns", :count), Column.new("Returned value", :money) ]
    end

    def cashier_figures
      @cashier_figures ||= begin
        sales = completed_sales.group(:cashier_id).pluck(:cashier_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(sales.discount_cents)"),
          Arel.sql("COUNT(*) FILTER (WHERE sales.discount_cents > 0)")).to_h { |id, *figures| [ id, figures.map(&:to_i) ] }
        # Line discounts, and sales discounted only on their lines (not already counted above).
        lines = discounted_lines.group("sales.cashier_id").pluck(Arel.sql("sales.cashier_id"), Arel.sql("SUM(sale_lines.discount_cents)"),
          Arel.sql("COUNT(DISTINCT sale_lines.sale_id) FILTER (WHERE sales.discount_cents = 0)")).to_h { |id, *figures| [ id, figures.map(&:to_i) ] }
        voids = voided_sales.group(:cashier_id).pluck(:cashier_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(total_cents)")).to_h { [ _1, [ _2, _3.to_i ] ] }
        returned = returns.group(:creator_id).pluck(:creator_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(total_cents)")).to_h { [ _1, [ _2, _3.to_i ] ] }

        account.users.where(id: sales.keys | voids.keys | returned.keys).sort_by(&:name).map do |user|
          count, discount, discounted = sales.fetch(user.id, [ 0, 0, 0 ])
          line_discount, discounted_on_lines = lines.fetch(user.id, [ 0, 0 ])
          [ user.name, count, discount + line_discount, discounted + discounted_on_lines, *voids.fetch(user.id, [ 0, 0 ]), *returned.fetch(user.id, [ 0, 0 ]) ]
        end
      end
    end

    def discounted_lines
      sold_lines.where("sale_lines.discount_cents > 0")
    end

    def cashier_rows = cashier_figures

    def cashier_totals
      [ "Total", *(1..7).map { |index| cashier_figures.sum { _1[index] } } ]
    end

    def void_columns
      [ Column.new("Receipt", :link), Column.new("Voided", :text), Column.new("Cashier", :text), Column.new("Voided by", :text),
        Column.new("Reason", :text), Column.new("Total", :money) ]
    end

    def void_rows
      voided_sales.includes(:branch, :cashier, :voided_by).order(:voided_at).map do |sale|
        [ Link.new(sale.receipt_number, sale), I18n.l(sale.voided_at, format: :short), sale.cashier.name, sale.voided_by&.name, sale.void_reason, sale.total_cents ]
      end
    end

    def discount_columns
      [ Column.new("Receipt", :link), Column.new("Date", :text), Column.new("Cashier", :text), Column.new("Approved by", :text),
        Column.new("Discount", :money), Column.new("% of sale", :percent) ]
    end

    def discount_rows
      discounts = completed_sales.where("sales.discount_cents > 0").pluck(:id, :discount_cents).to_h
      discounted_lines.group(:sale_id).sum(:discount_cents).each { |id, cents| discounts[id] = discounts.fetch(id, 0) + cents }
      biggest = discounts.max_by(20, &:last).to_h

      account.sales.where(id: biggest.keys).includes(:branch, :cashier, :discount_approver).sort_by { -biggest[_1.id] }.map do |sale|
        discount = biggest[sale.id]
        [ Link.new(sale.receipt_number, sale), I18n.l(sale.completed_at, format: :short), sale.cashier.name,
          sale.discount_approver&.name || "Within the cashier's limit", discount, percent(discount, sale.total_cents + discount) ]
      end
    end
end
