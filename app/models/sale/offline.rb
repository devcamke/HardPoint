# Sales rung up while a till was offline, recorded when it's back. Each carries the ID the till
# gave it, so sending it again records nothing new, and the time it really happened. The till
# charged what its catalogue said; anything worth a second look (a price that has since gone
# up, stock taken below zero, a shift already closed) comes back as a warning and goes in
# Activity, rather than refusing a sale the customer has already paid for.
module Sale::Offline
  extend ActiveSupport::Concern

  Result = Data.define(:uuid, :status, :sale, :warnings, :error) do
    def as_json(*)
      { uuid: uuid, status: status, receipt_number: sale&.receipt_number, sale_id: sale&.id, warnings: warnings, error: error }
    end
  end

  # The till may be minutes or days behind; times outside the shift or in the future aren't trusted.
  CLOCK_TOLERANCE = 5.minutes

  included do
    # When an offline sale actually happened; completing it records that as its completion time.
    attr_accessor :happened_at

    scope :offline, -> { where.not(offline_uuid: nil) }
  end

  class_methods do
    def record_offline(data)
      data = data.to_h.deep_stringify_keys
      uuid = data["uuid"].to_s
      raise ArgumentError, "Missing sale ID" unless uuid.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      if (existing = find_by(offline_uuid: uuid))
        return Result.new(uuid, "duplicate", existing, [], nil)
      end

      sale = transaction { build_offline(data).tap(&:complete_offline) }
      Result.new(uuid, sale.completed? ? "recorded" : "needs_attention", sale, sale.offline_warnings, nil)
    rescue ActiveRecord::RecordNotUnique
      Result.new(uuid, "duplicate", find_by(offline_uuid: uuid), [], nil)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
      Result.new(uuid, "error", nil, [], error.message)
    end

    private
      def build_offline(data)
        account = Current.account
        shift = account.shifts.find(data["shift_id"])
        cashier = account.users.find(data["cashier_id"])
        happened_at = Time.zone.parse(data["happened_at"].to_s) || Time.current
        happened_at = happened_at.clamp(shift.opened_at - CLOCK_TOLERANCE, Time.current + CLOCK_TOLERANCE)

        customer = account.customers.find(data["customer_id"]) if data["customer_id"].present?
        sale = create!(account: account, branch: shift.branch, register: shift.register, shift: shift, cashier: cashier, customer: customer,
          offline_uuid: data["uuid"], offline_receipt_number: data["receipt_number"].to_s.first(30).presence, created_at: happened_at)
        sale.happened_at = happened_at
        sale.offline_payments = Array(data["payments"])

        Array(data["lines"]).each do |line|
          product = account.products.find(line["product_id"])
          sale.lines.create!(account: account, product: product, product_unit: (product.product_units.find(line["product_unit_id"]) if line["product_unit_id"].present?),
            quantity: line["quantity"], unit_price_cents: line["unit_price_cents"].to_i, discount_cents: line["discount_cents"].to_i,
            promotion: (account.promotions.find_by(id: line["promotion_id"]) if line["promotion_id"].present?),
            promotion_discount_cents: line["promotion_id"].present? ? line["promotion_discount_cents"].to_i : 0,
            serial_number: line["serial_number"].presence)
        end
        sale.discount_cents = data["discount_cents"].to_i
        sale.recalculate
        sale.offline_expected_total_cents = data["total_cents"].to_i
        sale
      end
  end

  attr_accessor :offline_payments, :offline_expected_total_cents

  def offline_warnings
    @offline_warnings ||= []
  end

  def complete_offline
    Current.set(user: cashier) do
      offline_payments.each do |payment|
        break unless open?

        taken = pay(tender: payment["tender"].to_s, amount_cents: payment["amount_cents"]&.to_i, tendered_cents: payment["tendered_cents"]&.to_i,
          reference: payment["reference"].presence || (payment["tender"] == "mobile_money" ? "OFFLINE" : nil))
        offline_warnings << "#{taken.label} payment not recorded: #{taken.errors.full_messages.to_sentence}" if taken.errors.any?
      end
    end

    note_offline_differences
    track_event "recorded_offline", creator: cashier, offline_receipt_number: offline_receipt_number, happened_at: happened_at&.iso8601,
      warnings: offline_warnings.presence
  end

  private
    def note_offline_differences
      if offline_expected_total_cents.to_i != total_cents
        offline_warnings << "The till worked out #{Money.format(offline_expected_total_cents)}; the total is #{Money.format(total_cents)}"
      end
      offline_warnings << "#{Money.format(balance_due_cents)} is still due, so the sale is parked at #{register.name} for someone to finish" unless completed?
      update!(status: :parked) if open?

      lines.includes(:product, :product_unit, :promotion).each do |line|
        # The price this customer would get (their price list included), before any promotion.
        catalogue_price = line.product_unit ? line.product_unit.effective_price_cents : line.product.price_cents_for(quantity: line.quantity, price_list: price_list)
        if line.unit_price_cents < catalogue_price
          offline_warnings << "#{line.description} sold at #{Money.format(line.unit_price_cents)}; the price is now #{Money.format(catalogue_price)}"
        end
        if line.promotion && !line.promotion.status(happened_at.to_date).in?(%w[ running ])
          offline_warnings << "#{line.description}: #{line.promotion.name} wasn't running on #{I18n.l(happened_at.to_date, format: :long)} (it's #{line.promotion.status})"
        end
        if completed? && line.product.track_stock? && (stock = line.product.stock_at(branch)).negative?
          offline_warnings << "#{line.product.name} now shows #{stock.to_s("F").delete_suffix(".0")} in stock at #{branch.name}"
        end
      end
      offline_warnings << "#{shift.name} had already closed, so its cash count didn't include this sale" if shift.closed?
    end
end
