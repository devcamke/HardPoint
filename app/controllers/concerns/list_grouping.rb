# Odoo's "Group By" for a list page: one row per group with how many records it has and what they add up to,
# counted over the whole filtered list in the database (not just the page on screen). Each group opens to
# show its records, loaded when it's opened.
module ListGrouping
  extend ActiveSupport::Concern

  # value:  what the group's filter parameter is set to when it's opened ("none" for records without one)
  # totals: { currency code => cents }, empty when the list has no amounts to add up
  Group = Data.define(:value, :label, :count, :totals)

  included do
    helper_method :list_frame
  end

  private
    # column:   what to group by, e.g. :category_id or "suppliers.currency_code"
    # labels:   turns a group's value into its label (nil for records without one)
    # total:    the column to add up, if any
    # currency: the currency of the total (and of records whose currency_column is empty)
    # currency_column: the column giving each record's currency, when they differ; each currency gets its own total
    # order:    the values in the order to show them (statuses); otherwise groups are alphabetical
    def list_groups(scope, column, labels:, total: nil, currency: nil, currency_column: nil, order: nil)
      scope = scope.unscope(:order, :includes)
      totals = Hash.new { |hash, key| hash[key] = {} }
      if total && currency_column
        scope.group(column, currency_column).sum(total).each { |(value, code), cents| totals[value][code || currency] = totals[value].fetch(code || currency, 0) + cents }
      elsif total
        scope.group(column).sum(total).each { |value, cents| totals[value][currency] = cents }
      end

      groups = scope.group(column).count.map do |value, count|
        Group.new(value: value.nil? ? "none" : value.to_s, label: labels.call(value), count:, totals: totals[value])
      end
      order ? groups.sort_by { order.index(_1.value) || order.size } : groups.sort_by { [ _1.value == "none" ? 1 : 0, _1.label.downcase ] }
    end

    # The frame a grouped list's opened group loads into, or nil for the page itself.
    def list_frame
      params[:frame].to_s[/\Agroup_[\w-]+\z/]
    end
end
