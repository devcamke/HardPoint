module BillingsHelper
  STATUS_BADGES = {
    "trialing" => "bg-gray-50 text-gray-700", "active" => "bg-green-50 text-green-800", "payment_due" => "bg-amber-100 text-amber-800",
    "read_only" => "bg-red-50 text-red-800", "suspended" => "bg-gray-700 text-white"
  }.freeze

  def subscription_status_badge(account)
    label = account.trialing? && account.trial_days_left ? "Trial, #{pluralize(account.trial_days_left, "day")} left" : account.subscription_status.humanize
    badge = tag.span(label, class: "badge #{STATUS_BADGES[account.subscription_status]}")
    closing = tag.span("Closing", class: "badge ml-1 bg-red-50 text-red-800", title: "Data deleted #{l(account.deletion_scheduled_for.to_date, format: :long)}") if account.closing?
    safe_join [ badge, closing ].compact
  end
end
