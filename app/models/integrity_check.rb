# Money software earns trust by never being wrong. Every night (IntegrityCheckJob) these checks look across
# every shop for the things that must always hold and say so when one doesn't: receipt numbers with no gaps,
# stock on hand equal to the ledger, completed sales paid in full, closed shifts counted, M-Pesa money nobody
# has matched to a sale. A finding is a bug or tampering until shown otherwise; the operators are emailed, and
# the admin Database page shows the last run.
class IntegrityCheck
  Finding = Data.define(:check, :account_id, :count, :detail) do
    def description = "#{check.to_s.humanize}: #{detail}"
  end

  CACHE_KEY = "integrity_check:last"
  UNMATCHED_MPESA_AFTER = 1.day

  def self.run = new.tap(&:findings)

  # The last run's outcome, as the admin page and the platform checks see it: { ran_at:, findings: [ { … } ] } or nil.
  def self.last = Rails.cache.read(CACHE_KEY)

  def findings
    @findings ||= Account.without_isolation { %i[ receipt_gaps return_number_gaps stock_mismatch unbalanced_sales uncounted_shifts unmatched_mpesa ].flat_map { send(_1) } }
  end

  def clean? = findings.empty?
  def ran_at = @ran_at ||= Time.current

  def remember!
    Rails.cache.write(CACHE_KEY, { ran_at: ran_at, findings: findings.map(&:to_h) }, expires_in: 3.days)
  end

  # One line per shop for the alert email.
  def summary
    findings.group_by(&:account_id).map do |account_id, found|
      shop = Account.find_by(id: account_id)
      "#{shop&.name || "shop #{account_id}"} (#{shop&.subdomain}):\n#{found.map { "  - #{_1.description}" }.join("\n")}"
    end.join("\n")
  end

  private
    # Receipt numbers are a gap-free sequence per branch, handed out by DocumentSequence: every number the counter
    # has issued must still be on a sale, so fewer numbered sales than the counter means one was deleted.
    def receipt_gaps
      gaps_in "sales", "sale", :receipt_gaps, "receipt"
    end

    def return_number_gaps
      gaps_in "sale_returns", "return", :return_number_gaps, "return"
    end

    def gaps_in(table, kind, check, noun)
      rows = select_rows(<<~SQL)
        SELECT seq.account_id, seq.branch_id, seq.last_number - count(t.id) AS missing
        FROM document_sequences seq LEFT JOIN #{table} t ON t.branch_id = seq.branch_id AND t.number IS NOT NULL
        WHERE seq.kind = '#{kind}'
        GROUP BY seq.account_id, seq.branch_id, seq.last_number HAVING seq.last_number <> count(t.id)
      SQL
      rows.map { |account_id, branch_id, missing| Finding.new(check, account_id, missing.to_i, "#{missing} #{noun} #{"number".pluralize(missing.to_i)} missing at branch #{branch_id}") }
    end

    # Stock on hand is the sum of the ledger, product by product and branch by branch; nothing else writes it.
    def stock_mismatch
      rows = select_rows(<<~SQL)
        SELECT COALESCE(l.account_id, m.account_id), COALESCE(l.branch_id, m.branch_id), COALESCE(l.product_id, m.product_id), COALESCE(l.quantity, 0), COALESCE(m.total, 0)
        FROM stock_levels l
        FULL OUTER JOIN (SELECT account_id, branch_id, product_id, sum(quantity) AS total FROM stock_movements GROUP BY 1, 2, 3) m
          ON m.branch_id = l.branch_id AND m.product_id = l.product_id
        WHERE COALESCE(l.quantity, 0) <> COALESCE(m.total, 0)
      SQL
      rows.group_by(&:first).map do |account_id, mismatches|
        worst = mismatches.max_by { |(_, _, _, level, ledger)| (level.to_d - ledger.to_d).abs }
        Finding.new(:stock_mismatch, account_id, mismatches.size,
          "#{mismatches.size} #{"product".pluralize(mismatches.size)} whose stock on hand isn't the sum of the ledger (e.g. product #{worst[2]} at branch #{worst[1]}: #{worst[3]} on hand, ledger #{worst[4]})")
      end
    end

    # A completed sale's payments add up to its total, to the cent.
    def unbalanced_sales
      rows = select_rows(<<~SQL)
        SELECT s.account_id, s.id, s.total_cents, COALESCE(sum(p.amount_cents), 0)
        FROM sales s LEFT JOIN payments p ON p.sale_id = s.id
        WHERE s.status = 'completed'
        GROUP BY s.id HAVING s.total_cents <> COALESCE(sum(p.amount_cents), 0)
      SQL
      rows.group_by(&:first).map do |account_id, sales|
        sale = sales.first
        Finding.new(:unbalanced_sales, account_id, sales.size, "#{sales.size} completed #{"sale".pluralize(sales.size)} whose payments don't add up to the total (e.g. sale #{sale[1]}: total #{sale[2]}, paid #{sale[3]})")
      end
    end

    # Every closed shift was counted: the Z report rests on that number.
    def uncounted_shifts
      rows = select_rows("SELECT account_id, count(*) FROM shifts WHERE status = 'closed' AND counted_cash_cents IS NULL GROUP BY account_id")
      rows.map { |account_id, count| Finding.new(:uncounted_shifts, account_id, count.to_i, "#{count} closed #{"shift".pluralize(count.to_i)} without a cash count") }
    end

    # Money that arrived on the Paybill and was matched to nothing for a day: a sale that wasn't rung up, or a typo.
    def unmatched_mpesa
      rows = select_rows(ActiveRecord::Base.sanitize_sql_array([ "SELECT account_id, count(*), sum(amount_cents) FROM mpesa_transactions WHERE matched_id IS NULL AND transacted_at < ? GROUP BY account_id", UNMATCHED_MPESA_AFTER.ago ]))
      rows.map { |account_id, count, cents| Finding.new(:unmatched_mpesa, account_id, count.to_i, "#{count} M-Pesa #{"payment".pluralize(count.to_i)} (#{Money.format(cents.to_i)}) matched to nothing for more than a day") }
    end

    def select_rows(sql) = ActiveRecord::Base.connection.select_rows(sql)
end
