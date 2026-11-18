# Goods rung up and then taken off again before any payment: a line removed, a quantity cut, or the whole sale
# cleared. An honest till does it all day (a wrong scan, a customer who changes their mind), but it's also how cash
# goes missing without a trace: ring up, take the money, clear the sale. So each one is kept in Activity against
# the till, since a cleared sale leaves nothing behind to hang it on. CashierPatterns sets each cashier's day
# beside their usual, the shift's page lists them, and the discounts and voids report counts them per cashier.
module Sale::TakenOff
  extend ActiveSupport::Concern

  ACTIONS = %w[ sale_cleared line_removed quantity_reduced ].freeze

  # Each one taken off a till between two times, oldest first.
  def self.at(register, from, to)
    Event.where(account_id: register.account_id, eventable: register, action: ACTIONS, created_at: from..to).includes(:creator).order(:created_at)
  end

  # What an entry took off, in words: "cleared a sale: 10 × Cement 50 kg and 2 × Wheelbarrow".
  def self.words(event)
    particulars = event.particulars
    case event.action
    when "sale_cleared" then "cleared a sale: #{Array(particulars["items"]).to_sentence}"
    when "line_removed" then "removed #{particulars["item"]}"
    when "quantity_reduced" then "cut #{particulars["item"]} from #{particulars["from"]} to #{particulars["to"]}"
    end
  end

  def record_cleared
    record_taken_off "sale_cleared", value: total_cents, items: lines.map { Sale::TakenOff.item_words(_1) }
  end

  # Called with the line as it was, once it's gone.
  def record_line_removed(line)
    record_taken_off "line_removed", value: line.total_cents, item: Sale::TakenOff.item_words(line)
  end

  def record_quantity_reduced(line, from:, value_cents:)
    record_taken_off "quantity_reduced", value: value_cents, item: line.description,
      from: Sale::TakenOff.quantity_words(from), to: Sale::TakenOff.quantity_words(line.quantity)
  end

  def self.item_words(line) = "#{quantity_words(line.quantity)} × #{line.description}"
  def self.quantity_words(quantity) = quantity.to_d.to_s("F").delete_suffix(".0")

  private
    def record_taken_off(action, value:, **particulars)
      register.track_event action, value: value, shift: shift.name, shift_id: shift_id, sale_id: id, customer: customer&.name, **particulars
    end
end
