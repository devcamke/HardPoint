module BillingsHelper
  STATUS_TONES = { "trialing" => :neutral, "active" => :success, "payment_due" => :warning, "read_only" => :danger, "suspended" => :dark }.freeze

  def subscription_status_badge(account)
    label = account.trialing? && account.trial_days_left ? "Trial, #{pluralize(account.trial_days_left, "day")} left" : account.subscription_status.humanize
    badge = status_dot(label, STATUS_TONES.fetch(account.subscription_status, :neutral))
    closing = status_dot("Closing", :danger, class: "ml-2", title: "Data deleted #{l(account.deletion_scheduled_for.to_date, format: :long)}") if account.closing?
    safe_join [ badge, closing ].compact
  end
end
