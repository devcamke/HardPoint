# A hire: which tools a customer has, from when and until when. The money (deposit, then the hire
# and damage charges) lives on a customer order of source "hire", so the deposit is taken and the
# hire settled at the till exactly like any order, with a receipt and KRA eTIMS invoice.
class HireAgreement < ApplicationRecord
  include AccountOwned, Eventable

  belongs_to :branch
  belongs_to :customer
  belongs_to :customer_order
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, -> { order(:id) }, class_name: "HireLine", dependent: :destroy, inverse_of: :hire_agreement
  has_many :hire_items, through: :lines

  enum :status, %w[ out returned cancelled ].index_by(&:itself), default: "out"

  validates :id_number, length: { maximum: 30 }
  validates :site, :note, length: { maximum: 250 }
  validate { errors.add :due_back_at, "must be after it goes out" if due_back_at && started_at && due_back_at <= started_at }
  validates_same_account :branch, :customer

  before_create { self.number = DocumentSequence.next_number(branch, "hire_agreement") }
  after_create { track_event "created", customer: customer.name, tools: hire_items.map(&:label).to_sentence }

  scope :chronologically, -> { order(started_at: :desc, id: :desc) }
  scope :overdue, -> { out.where(due_back_at: ...Time.current) }

  # Hires tools out: checks they're free at the branch, opens the order (with the estimated charge
  # for the planned period, so the deposit and printed agreement show it) and marks them on hire.
  def self.hire_out(branch:, customer:, items:, due_back_at:, started_at: Time.current, **details)
    agreement = new(account: branch.account, branch: branch, customer: customer, started_at: started_at, due_back_at: due_back_at, **details)
    agreement.validate
    agreement.errors.delete(:customer_order) # made below, with the lines
    agreement.errors.add :base, "Choose at least one tool" if Array(items).empty?
    return agreement if agreement.errors.any?

    transaction do
      # Locked and read afresh, so two people can't hire out the same tool at once.
      items = branch.account.hire_items.where(id: Array(items).map(&:id)).lock.order(:id).to_a
      items.reject { _1.available? && _1.branch_id == branch.id }.each { agreement.errors.add :base, "#{_1.label} isn't available at #{branch.name}" }
      raise ActiveRecord::Rollback if agreement.errors.any?

      items.each { agreement.lines.build(account: agreement.account, hire_item: _1, daily_rate_cents: _1.daily_rate_cents, weekly_rate_cents: _1.weekly_rate_cents) }
      agreement.customer_order = agreement.account.customer_orders.create!(branch: branch, customer: customer, status: :ordered,
        ordered_at: started_at, source: "hire", note: "Tool hire", lines_attributes: agreement.estimate_lines)
      agreement.save!
      items.each { _1.update!(status: "on_hire") }
    end
    agreement
  end

  def reference
    "#{branch.code}-H#{number.to_s.rjust(5, "0")}"
  end
  alias_method :event_name, :reference

  def overdue?
    out? && due_back_at < Time.current
  end

  def deposit_due_cents
    hire_items.sum(:deposit_cents)
  end

  def planned_days
    HireLine.days_between(started_at, due_back_at)
  end

  # Order lines for what the hire will cost if everything comes back on time.
  def estimate_lines
    lines.map do |line|
      charge = line.charge_until(due_back_at)
      hire_line_attributes charge, "#{line.hire_item.label}, #{planned_days} #{"day".pluralize(planned_days)} (estimate)"
    end
  end

  # Tools brought back. `returns` maps hire line ids to what came back: { condition_note:, damage:,
  # damage_note:, needs_repair: }. When the last one is back, the order gets the actual charges and is
  # ready to settle at the till.
  def return_tools(returns, at: Time.current)
    transaction do
      lines.reject(&:returned?).each do |line|
        details = returns[line.id] || returns[line.id.to_s] or next
        line.return(at: at, condition_note: details[:condition_note], damage_cents: Monetary.to_cents(details[:damage]).to_i,
          damage_note: details[:damage_note], needs_repair: ActiveModel::Type::Boolean.new.cast(details[:needs_repair]))
      end
      track_event "tools_returned", tools: lines.select { _1.returned_at == at }.map { _1.hire_item.label }.to_sentence
      finish(at) if lines.all?(&:returned?)
    end
  end

  def extend_to(time)
    return errors.add(:base, "Only a hire that's out can be extended") && false unless out?
    return errors.add(:due_back_at, "must be later than now") && false unless time > Time.current

    transaction do
      update!(due_back_at: time, reminded_at: nil)
      replace_order_lines(estimate_lines)
      track_event "extended", until: time.iso8601
    end
    true
  end

  # Tools that never left (a hire made by mistake). The order is cancelled too, once any deposit is refunded.
  def cancel
    return errors.add(:base, "Only a hire that's out can be cancelled") && false unless out?

    transaction do
      unless customer_order.cancel(reason: "Hire #{reference} cancelled")
        errors.add :base, customer_order.errors.full_messages.to_sentence
        raise ActiveRecord::Rollback
      end
      hire_items.reload.each { _1.update!(status: "available") } # fresh: the list may predate hiring them out
      update!(status: "cancelled")
      track_event "cancelled"
    end
    cancelled?
  end

  def remind
    return false unless overdue? && account.sms_enabled? && (reminded_at.nil? || reminded_at < 1.day.ago)

    Sms::Message.hire_overdue(self).persisted?.tap { |sent| update!(reminded_at: Time.current) if sent }
  end

  def charges_cents
    lines.sum { _1.charge_cents.to_i + _1.damage_cents }
  end

  private
    def finish(at)
      update!(status: "returned", returned_at: at)
      replace_order_lines(lines.flat_map do |line|
        [ hire_line_attributes(line.charge_cents, "#{line.hire_item.label}, #{line.days_charged} #{"day".pluralize(line.days_charged)}"),
          (hire_line_attributes(line.damage_cents, "Damage to #{line.hire_item.label}#{": #{line.damage_note}" if line.damage_note}") if line.damage_cents.positive?) ]
      end.compact)
      customer_order.update!(status: :ready)
    end

    def replace_order_lines(attributes)
      order = customer_order
      order.lines.each(&:mark_for_destruction)
      attributes.each { order.lines.build(_1) }
      order.save!
    end

    def hire_line_attributes(cents, detail)
      { account: account, product: account.hire_product, quantity: 1, unit_price_cents: cents, detail: detail }
    end
end
