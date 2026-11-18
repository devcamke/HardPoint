# An order to a supplier for delivery to a branch: a draft while it's being put together, sent
# (emailed as a PDF), then partially or fully received through goods received notes. One the
# supplier can't finish is closed short, so the rest stops being waited for.
#
# Whoever raises orders shouldn't be able to commit the shop's money alone: once the orders one person has sent in
# a day come to more than the shop's limit (purchase_approval_above, on Shop details), sending another needs an
# owner or manager, at their own screen or by approval PIN. It's the day's orders, so one big order can't go as
# several small ones.
class PurchaseOrder < ApplicationRecord
  include AccountOwned, Eventable, Monetary

  belongs_to :supplier
  belongs_to :branch
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, -> { order(:id) }, class_name: "PurchaseOrderLine", dependent: :destroy, inverse_of: :purchase_order
  has_many :goods_receipts, dependent: :restrict_with_error

  enum :status, %w[ draft sent partially_received received closed cancelled ].index_by(&:itself), default: :draft

  money_attribute :total

  accepts_nested_attributes_for :lines, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["product_code"].blank? && attributes["quantity"].blank? }

  validates_same_account :supplier, :branch
  validate { errors.add :base, "Add at least one product" if lines.reject(&:marked_for_destruction?).empty? }
  validate :no_duplicate_products
  validate(on: :update) { errors.add :base, "Only a draft can be changed" if lines.any?(&:changed_for_autosave?) && status_was != "draft" }

  before_validation(on: :create) { self.exchange_rate ||= supplier&.current_rate }
  before_create { self.number = DocumentSequence.next_number(branch, "purchase_order") }
  before_save { self.total_cents = lines.reject(&:marked_for_destruction?).sum(&:line_total_cents) }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :open, -> { where(status: %w[ sent partially_received ]) }

  # Orders are in the supplier's currency; the rate on the day it was made is kept for reference.
  def currency = supplier.currency_code

  def reference
    "#{branch.code}-PO#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  def receivable?
    sent? || partially_received?
  end

  def outstanding_lines
    lines.select { _1.outstanding_quantity.positive? }
  end

  # The order's worth in the shop's own money.
  def base_total_cents
    exchange_rate ? (total_cents * exchange_rate.to_d).round : total_cents
  end

  # What this person has already sent today (the shop's day) that's still on order, in the shop's money.
  def sent_earlier_today_cents(by = Current.user)
    midnight = Time.use_zone(account.time_zone) { Time.zone.now.beginning_of_day }
    sent = Event.where(account_id: account_id, eventable_type: "PurchaseOrder", action: "sent", creator: by, created_at: midnight..).select(:eventable_id)
    account.purchase_orders.where(id: sent).where.not(id: id).where.not(status: "cancelled").sum(&:base_total_cents)
  end

  def needs_approval?(by = Current.user)
    base_total_cents + sent_earlier_today_cents(by) > account.purchase_approval_above_cents
  end

  def approval_needed_message(by = Current.user)
    so_far = " (#{Money.format(sent_earlier_today_cents(by))} already today)" if sent_earlier_today_cents(by).positive?
    "This order is worth #{Money.format(base_total_cents)}#{so_far}. Sending more than #{Money.format(account.purchase_approval_above_cents)} " \
      "of orders in a day needs a manager's approval PIN"
  end

  def mark_sent(approver: nil)
    draft? && update(status: :sent, sent_at: Time.current).tap { |sent| track_event "sent", supplier: supplier.name, total: total_cents, approver: approver if sent }
  end

  def cancel
    (draft? || sent?) && update(status: :cancelled).tap { |cancelled| track_event "cancelled" if cancelled }
  end

  # The supplier can't send the rest: what's still to come is written off the order, so Reorder stops
  # counting on it and suggests it again. An order with nothing received is cancelled instead.
  def close(user = Current.user)
    return false unless partially_received?

    short = lines.select { _1.outstanding_quantity.positive? }.map { "#{_1.outstanding_quantity.to_s("F").delete_suffix(".0")} #{_1.product.name}" }
    update(status: :closed).tap { |closed| track_event "closed", creator: user, short: short.to_sentence if closed }
  end

  def refresh_receipt_status
    lines.reload
    update!(status: lines.all? { _1.outstanding_quantity <= 0 } ? :received : :partially_received)
  end

  private
    def no_duplicate_products
      duplicates = lines.reject(&:marked_for_destruction?).filter_map(&:product).tally.select { |_, count| count > 1 }.keys
      errors.add :base, "#{duplicates.map(&:name).to_sentence} is listed more than once" if duplicates.any?
    end
end
