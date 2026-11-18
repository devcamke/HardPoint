# Who said yes to what: every void, discount, payout, write-off and purchase that needed an owner or manager,
# by who asked and who approved, and each one somebody approved for themselves. Two things show here that
# nothing else catches: a manager waving their own actions through (they may, unless the shop asks for a second
# approver), and the same two people always approving for each other.
class Report::Approvals < Report
  self.title = "Approvals"
  self.description = "Who approved what for whom, and what owners and managers approved for themselves"
  self.group = "Sales and money"

  # What each approved entry in Activity is, and which of its particulars holds its worth.
  KINDS = {
    %w[ Sale voided ] => [ "Void", "total" ],
    %w[ Sale discount_approved ] => [ "Discount over the limit", nil ],
    %w[ Sale completed_without_payment ] => [ "Sale with nothing to pay", "total" ],
    %w[ Sale credit_approved ] => [ "Credit over the limit", "amount" ],
    %w[ CustomerOrder credit_approved ] => [ "Credit over the limit", "amount" ],
    %w[ CustomerOrder deposit_kept ] => [ "Deposit kept", "amount" ],
    %w[ Customer written_off ] => [ "Debt written off", "amount" ],
    %w[ Shift payout_approved ] => [ "Payout from a till", "amount" ],
    %w[ Product write_off_approved ] => [ "Stock written off", "value" ],
    %w[ PurchaseOrder sent ] => [ "Purchase order", "total" ],
    %w[ GoodsReceipt received ] => [ "Goods received without an order", "unordered" ]
  }.freeze

  Approved = Data.define(:event, :kind, :value_cents) do
    def self_approved? = event.particulars["self_approved"].present?
    def asked_by = event.creator&.name || "HardPoint"
    def approved_by = self_approved? ? "Themselves" : event.particulars["approver"]
  end

  # Every approval in a period, oldest first.
  def self.approved(account, range)
    Event.where(account: account, created_at: range).where("particulars ? 'approver'").includes(:creator).order(:created_at).filter_map do |event|
      kind, worth = KINDS[[ event.eventable_type, event.action ]]
      Approved.new(event, kind, (event.particulars[worth].to_i if worth)) if kind
    end
  end

  def sections
    [ Section.new(title: "Who approved for whom", columns: pair_columns, rows: pair_rows,
        note: "Themselves means an owner or manager approved their own action. Who needs a second person is set under Settings › Shop details."),
      Section.new(title: "Approved for themselves", columns: own_columns, rows: own_rows) ]
  end

  private
    def approved
      @approved ||= self.class.approved(account, period.range)
    end

    def pair_columns
      [ Column.new("Asked by", :text), Column.new("Approved by", :text), Column.new("Approvals", :count), Column.new("Value", :money) ]
    end

    def pair_rows
      approved.group_by { [ _1.asked_by, _1.approved_by ] }.map { |(asked_by, approved_by), all| [ asked_by, approved_by, all.size, all.sum { _1.value_cents.to_i } ] }
        .sort_by { [ -_1[2], _1[0] ] }
    end

    def own_columns
      [ Column.new("When", :text), Column.new("Who", :text), Column.new("What", :text), Column.new("On", :text), Column.new("Value", :money) ]
    end

    def own_rows
      approved.select(&:self_approved?).map { [ I18n.l(_1.event.created_at, format: :short), _1.asked_by, _1.kind, _1.event.particulars["name"], _1.value_cents ] }
    end
end
