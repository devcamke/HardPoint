# A sale at a till. It starts "open" (the cart), can be parked and recalled, and is completed once
# payments cover the total: it then gets its receipt number and its stock leaves the branch, in one
# transaction. Prices include tax; tax is worked out from each line's rate.
class Sale < ApplicationRecord
  include AccountOwned, Eventable, Monetary, Cart, Bundles, Payable, Voidable, Offline, Fundis, PublishesWebhooks

  after_update_commit if: -> { saved_change_to_status? && (completed? || voided?) } do
    publish_webhook(completed? ? "sale.completed" : "sale.voided")
  end

  belongs_to :branch
  belongs_to :register
  belongs_to :shift
  belongs_to :customer, optional: true
  belongs_to :cashier, class_name: "User", default: -> { Current.user }
  belongs_to :discount_approver, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
  belongs_to :credit_approver, class_name: "User", optional: true
  belongs_to :customer_order, optional: true
  belongs_to :job, optional: true
  belongs_to :fundi, optional: true
  has_many :delivery_notes, dependent: :restrict_with_error
  has_many :stk_requests, class_name: "Mpesa::StkRequest", dependent: :destroy
  has_many :airtel_requests, class_name: "Airtel::Request", dependent: :destroy
  has_one :etims_submission, -> { where(kind: "sale") }, class_name: "Etims::Submission", as: :document
  has_many :lines, -> { order(:id) }, class_name: "SaleLine", dependent: :destroy, inverse_of: :sale
  has_many :sale_returns, dependent: :restrict_with_error
  has_many :stock_movements, as: :source

  enum :status, %w[ open parked completed voided ].index_by(&:itself), default: :open

  money_attribute :discount, :subtotal, :tax, :total

  validates_same_account :branch, :register, :shift, :customer, :customer_order, :job, :fundi
  validate(if: :job) { errors.add :job, "must be one of the customer's jobs" unless job.customer_id == customer_id }
  validate(if: -> { job && will_save_change_to_job_id? }) { errors.add :job, "is closed" if job.closed? }

  # A job's spend changes, so API clients syncing jobs by updated_since pick it up.
  after_update_commit -> { job&.touch }, if: -> { saved_change_to_status? && (completed? || voided?) }
  after_update_commit -> { account.refresh_dashboard_later }, if: -> { saved_change_to_status? && (completed? || voided?) }
  after_update_commit -> { Etims::Submission.queue(self, kind: completed? ? "sale" : "credit_note") }, if: -> { saved_change_to_status? && (completed? || voided?) }

  scope :chronologically, -> { order(Arel.sql("COALESCE(sales.completed_at, sales.created_at) DESC"), id: :desc) }
  scope :finished, -> { where(status: %w[ completed voided ]) }

  def receipt_number
    number && "#{branch.code}-#{number.to_s.rjust(6, "0")}"
  end

  alias_method :name, :receipt_number

  def price_list
    customer&.price_list
  end

  # What the yard cuts for this sale, as the stock ledger recorded it: [ [ product, "2.5 m cut from a 6 m length, leaving a 3.5 m offcut" ], ... ]
  def cutting_list
    stock_movements.where(reason: "sold", product_id: account.products.cut_to_length.select(:id)).where.not(note: nil)
      .includes(:product).order(:id).map { [ _1.product, _1.note ] }
  end

  def returned_quantity(line)
    SaleReturnLine.where(sale_line: line).sum(:quantity)
  end

  def returnable?
    completed? && lines.any? { |line| returned_quantity(line) < line.quantity }
  end

  def self.find_by_receipt_number(receipt_number)
    code, number = receipt_number.to_s.strip.upcase.split("-", 2)
    joins(:branch).find_by(branches: { code: code }, number: number.to_i) if number.to_i.positive?
  end

  # The sales a receipt number as printed belongs to: the sale's own (MAIN-000123), or the one an offline till gave
  # it (MAIN-OFF1-K7Q2-0001), since that's what's on the paper a customer brings back. Tills before the device code
  # could repeat an offline number, so there may be more than one.
  def self.with_receipt_number(receipt_number)
    query = receipt_number.to_s.strip.upcase
    where(id: find_by_receipt_number(query)&.id).or(where(offline_receipt_number: query))
  end
end
