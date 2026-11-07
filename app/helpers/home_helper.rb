# Home for owners and managers: a "Needs you today" list where each row is one thing to act on, with the
# button that does it, most costly first. Built from the dashboard's own numbers, and only from what this
# person may act on (docs/SIMPLIFY.md, change 2).
module HomeHelper
  HomeTask = Data.define(:key, :tone, :title, :detail, :action, :path)

  def home_tasks(dashboard, membership = current_membership)
    account, branch = dashboard.account, dashboard.branch
    in_branch = ->(scope) { branch ? scope.where(branch: branch) : scope }
    tasks = []

    if (count = account.etims_submissions.failed.count).positive?
      tasks << HomeTask.new(:etims, :danger, "#{pluralize(count, "sale")} refused by KRA eTIMS",
        "Their receipts aren't signed until they're sent again", "See why", etims_submissions_path(status: "failed"))
    end

    if (count = dashboard.low_stock_count).positive?
      tasks << HomeTask.new(:low_stock, :warning, "#{pluralize(count, "product")} running low", branch ? "At #{branch.name}" : "Across your branches",
        membership.can_purchase? ? "Order them" : "See which", reorder_list_path(branch_id: branch&.id))
    end

    owed = dashboard.owed_to_us
    if membership.can_manage_receivables? && owed[:overdue].positive?
      tasks << HomeTask.new(:customers_overdue, :danger, "#{money(owed[:overdue])} overdue from #{pluralize(owed[:overdue_customers], "customer")}",
        "#{money(owed[:total])} owed to you in all", "See who", receivables_path)
    end

    owing = dashboard.owed_by_us
    if membership.can_manage_payables? && owing[:overdue].positive?
      tasks << HomeTask.new(:suppliers_overdue, :danger, "#{money(owing[:overdue])} overdue to #{pluralize(owing[:overdue_suppliers], "supplier")}",
        "#{money(owing[:total])} owed to suppliers in all", "Review", payables_path)
    end

    if membership.can_approve_stock_counts? && (count = in_branch.(account.stock_counts.submitted).count).positive?
      tasks << HomeTask.new(:stock_counts, :info, "#{pluralize(count, "stock take")} waiting for your approval",
        "Stock doesn't change until it's approved", "Review", stock_counts_path)
    end

    if (count = in_branch.(account.shifts.open.where(opened_at: ...Time.zone.today.beginning_of_day)).count).positive?
      tasks << HomeTask.new(:shifts, :warning, "#{pluralize(count, "shift")} left open from an earlier day",
        "Close them to count the cash", "See shifts", shifts_path)
    end

    if (count = dashboard.orders_ready_count).positive?
      tasks << HomeTask.new(:orders_ready, :info, "#{pluralize(count, "order")} ready for collection", "Waiting at the counter",
        "View", customer_orders_path(status: "ready"))
    end

    if account.feature?(:deliveries) && (count = dashboard.deliveries_outstanding_count).positive?
      tasks << HomeTask.new(:deliveries, :info, "#{pluralize(count, "delivery", plural: "deliveries")} to send out", "Not delivered yet",
        "View", delivery_notes_path)
    end

    tasks
  end

  # The common places to start from Home, limited to what this person can do.
  def home_quick_actions(membership = current_membership)
    [
      ([ "New product", new_product_path ] if membership.can_manage_catalogue?),
      ([ "New quote", new_customer_order_path ] if membership.can_sell?),
      ([ "Receive goods", new_goods_receipt_path ] if membership.can_purchase?),
      ([ "Count stock", new_stock_count_path ] if membership.can_manage_stock?)
    ].compact
  end
end
