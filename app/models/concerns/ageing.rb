# Ageing of what's still owed, by days past the due date. Used for what customers owe the shop
# (receivables) and what the shop owes suppliers (payables). Includers define #open_invoices,
# whose items respond to #outstanding_cents and #days_overdue.
module Ageing
  BUCKETS = { "current" => ..0, "1_30" => 1..30, "31_60" => 31..60, "61_90" => 61..90, "over_90" => 91.. }.freeze

  def ageing(as_of: Date.current)
    Ageing.buckets_for(open_invoices, as_of: as_of)
  end

  # What's outstanding in each bucket, for anything with #outstanding_cents and #days_overdue.
  def self.buckets_for(open_items, as_of: Date.current)
    BUCKETS.transform_values { 0 }.tap do |buckets|
      open_items.each do |open|
        bucket = BUCKETS.find { |_, days| days.cover?(open.days_overdue(as_of)) }.first
        buckets[bucket] += open.outstanding_cents
      end
    end
  end

  # Past due: everything not in the current bucket.
  def self.overdue_in(buckets) = buckets.except("current").values.sum

  def overdue_cents(as_of: Date.current)
    open_invoices.select { _1.days_overdue(as_of).positive? }.sum(&:outstanding_cents)
  end
end
