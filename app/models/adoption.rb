# Is the simpler layout working? The measures from docs/SIMPLIFY.md, "How we'll know it worked", across every
# shop, for the platform admin. Read inside Account.without_isolation.
class Adoption
  # When the six areas, Home's to-do list, feature switches and search went live.
  SIMPLIFIED_ON = Date.new(2026, 11, 7)
  COHORT = 90.days
  WINDOW = 30.days
  LOST_WORDS = [ "where is", "where are", "where do", "how do i", "can't find", "cannot find", "cant find", "where did" ].freeze

  Cohort = Data.define(:label, :shops, :selling, :within_week, :median_days)

  # Time from signing up to the first sale, for shops that joined in the 90 days before the change and since.
  def first_sale_cohorts(today: Date.current)
    [ cohort("Signed up in the #{COHORT.in_days.to_i} days before", (SIMPLIFIED_ON - COHORT)...SIMPLIFIED_ON),
      cohort("Signed up since #{SIMPLIFIED_ON.to_fs(:long)}", SIMPLIFIED_ON..today) ]
  end

  # [ feature, shops with it on ] for each optional feature, out of shops_count.
  def features
    on = Account.where(deletion_scheduled_for: nil).pluck(:features).flatten.tally
    Account::Features::FEATURES.map { [ _1, on.fetch(_1.key, 0) ] }.sort_by { -_2 }
  end

  def shops_count
    @shops_count ||= Account.where(deletion_scheduled_for: nil).count
  end

  # [ name, times used, shops using it ] over the last 30 days, most used first.
  def shortcuts(since: WINDOW.ago.to_date)
    UsageCount.where(on: since..).group(:name).pluck(:name, Arel.sql("SUM(count)"), Arel.sql("COUNT(DISTINCT account_id)"))
      .sort_by { -_2 }
  end

  # Support requests that read like "where is …" or "how do I …", this 30 days against the 30 before.
  def lost_requests(today: Date.current)
    current = today - WINDOW.in_days.to_i + 1
    { recent: lost_scope.where(created_at: current.beginning_of_day..).count,
      before: lost_scope.where(created_at: (current - WINDOW.in_days.to_i).beginning_of_day...current.beginning_of_day).count,
      examples: lost_scope.order(created_at: :desc).limit(5).pluck(:subject, :created_at) }
  end

  def self.label(name)
    group, key = name.split(":", 2)
    case group
    when "search" then "Search: opened a #{key == "actions" ? "suggested action" : key.singularize}"
    when "home" then key == "start_selling" ? "Home: Start selling" : "Home: #{key.humanize(capitalize: false)}"
    when "quick" then "Quick action: #{key.humanize(capitalize: false)}"
    else { "reorder_draft_all" => "Reorder: drafted every supplier's order at once", "product_add_another" => "Product form: Add and start another",
           "till_opened_straight" => "Counter computer opened straight into the till" }.fetch(name, name)
    end
  end

  private
    def cohort(label, range)
      first_sales = Sale.where(status: "completed").group(:account_id).minimum(:completed_at)
      joined = Account.where(created_at: range.begin.beginning_of_day..(range.exclude_end? ? range.end.beginning_of_day - 1 : range.end.end_of_day))
        .pluck(:id, :created_at)
      # A sale dated before signing up is history brought in from elsewhere: count it as selling on day 0.
      days = joined.filter_map { |id, created_at| first_sales[id] && [ (first_sales[id] - created_at) / 1.day, 0 ].max }
      Cohort.new(label, joined.size, days.size, days.count { _1 <= 7 }, median(days))
    end

    def median(values)
      return if values.empty?

      sorted = values.sort
      middle = sorted.size / 2
      (sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0).round(1)
    end

    def lost_scope
      LOST_WORDS.inject(SupportRequest.none) do |scope, words|
        like = "%#{SupportRequest.sanitize_sql_like(words)}%"
        scope.or(SupportRequest.where("support_requests.subject ILIKE :like OR support_requests.body ILIKE :like", like: like))
      end
    end
end
