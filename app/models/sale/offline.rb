# Sales rung up while a till was offline, recorded when it's back. Each carries the ID the till
# gave it, so sending it again records nothing new, and the time it really happened. The till
# charged what its catalogue said; anything worth a second look (a price that has since gone
# up, stock taken below zero, a shift already closed, points already spent on another till) comes
# back as a warning and goes in Activity, rather than refusing a sale the customer has already paid for.
# A sale that can't be recorded at all (a product deleted since, a cashier who has left) is refused,
# and the refusal goes in Activity with what the till sent, once per sale: the money is in the drawer,
# so a manager has to know.
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
    # register: the till the sales are sent from. Its own shifts are the only ones they can go in.
    def record_offline(data, register: nil)
      data = data.to_h.deep_stringify_keys
      uuid = data["uuid"].to_s
      raise ArgumentError, "Missing sale ID" unless uuid.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)

      if (existing = find_by(offline_uuid: uuid))
        return Result.new(uuid, "duplicate", existing, [], nil)
      end

      sale = transaction { build_offline(data, register: register).tap(&:complete_offline) }
      Result.new(uuid, sale.completed? ? "recorded" : "needs_attention", sale, sale.offline_warnings, nil)
    rescue ActiveRecord::RecordNotUnique
      Result.new(uuid, "duplicate", find_by(offline_uuid: uuid), [], nil)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => error
      note_offline_refusal(data, uuid, error.message, register: register)
      Result.new(uuid, "error", nil, [], error.message)
    end

    private
      # Activity keeps the refused sale: the till, the time, the cashier, the total and what went wrong, so a
      # manager can ring it up by hand. Once per sale ID, however many times the till sends it.
      def note_offline_refusal(data, uuid, message, register:)
        account = Current.account
        return if account.account_events.where(action: "offline_sale_refused").where("particulars->>'uuid' = ?", uuid).exists?

        shift = account.shifts.find_by(id: data["shift_id"])
        subject = register || shift&.register || account
        cashier = account.users.find_by(id: data["cashier_id"])
        subject.track_event "offline_sale_refused", creator: cashier,
          uuid: uuid, receipt_number: data["receipt_number"].to_s.first(30).presence, happened_at: data["happened_at"].to_s.presence,
          total: data["total_cents"].to_i, cashier: cashier&.name, lines: Array(data["lines"]).size, error: message,
          payments: Array(data["payments"]).map { |payment| "#{payment["tender"]} #{Money.format(payment["amount_cents"] || payment["tendered_cents"])}" }
      rescue StandardError => failure
        Rails.error.report(failure, handled: true, context: { offline_uuid: uuid })
      end

      def build_offline(data, register:)
        account = Current.account
        shift = (register ? account.shifts.where(register: register) : account.shifts).find_by(id: data["shift_id"])
        raise ArgumentError, "The sale's shift isn't one of this till's" unless shift
        cashier = account.users.find(data["cashier_id"])
        raise ArgumentError, "#{cashier.name} can't sell at this shop" unless account.memberships.find_by(user: cashier)&.can_sell?
        happened_at = Time.zone.parse(data["happened_at"].to_s) || Time.current
        happened_at = happened_at.clamp(shift.opened_at - CLOCK_TOLERANCE, Time.current + CLOCK_TOLERANCE)

        customer = account.customers.find(data["customer_id"]) if data["customer_id"].present?
        job = customer.jobs.find_by(id: data["job_id"]) if customer && data["job_id"].present?
        sale = create!(account: account, branch: shift.branch, register: shift.register, shift: shift, cashier: cashier, customer: customer,
          job: (job if job&.open?), offline_uuid: data["uuid"], offline_receipt_number: data["receipt_number"].to_s.first(30).presence, created_at: happened_at)
        sale.happened_at = happened_at
        sale.offline_warnings << "#{job.label} had been closed, so the sale isn't tagged to it" if job&.closed?
        sale.offline_payments = Array(data["payments"])

        # Hand discounts need the till online (the offline till never sends one), so one arriving here is ignored.
        hand_discount_cents = data["discount_cents"].to_i + Array(data["lines"]).sum { _1["discount_cents"].to_i }
        sale.offline_warnings << "A hand discount of #{Money.format(hand_discount_cents)} was ignored: discounts need the till online" unless hand_discount_cents.zero?

        Array(data["lines"]).each do |line|
          raise ArgumentError, "A price can't be negative" if line["unit_price_cents"].to_i.negative? || line["promotion_discount_cents"].to_i.negative?
          product = account.products.find(line["product_id"])
          sale.lines.create!(account: account, product: product, product_unit: (product.product_units.find(line["product_unit_id"]) if line["product_unit_id"].present?),
            quantity: line["quantity"], unit_price_cents: line["unit_price_cents"].to_i, discount_cents: 0,
            promotion: (account.promotions.find_by(id: line["promotion_id"]) if line["promotion_id"].present?),
            promotion_discount_cents: line["promotion_id"].present? ? line["promotion_discount_cents"].to_i : 0,
            serial_number: line["serial_number"].presence)
        end
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

        tender, intended = payment["tender"].to_s, payment["amount_cents"]&.to_i
        # Cash pays what the till charged it with.
        taken = pay(tender: tender, amount_cents: intended, tendered_cents: payment["tendered_cents"]&.to_i,
          reference: payment["reference"].presence || (tender.in?(%w[ mobile_money airtel_money ]) ? "OFFLINE" : nil), cash_limit_cents: (intended if tender == "cash"))
        if taken.errors.any?
          offline_warnings << "#{taken.label} payment not recorded: #{taken.errors.full_messages.to_sentence}"
        end
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
