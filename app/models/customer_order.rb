# One document from quote to collection. A quote (valid until a date) is confirmed into an order,
# the order can take deposits and be marked ready when the goods are in, and the customer collects
# it by having it rung up at a till, where the deposit counts towards the payment.
class CustomerOrder < ApplicationRecord
  include AccountOwned, Eventable, Monetary, Fulfilment, PublishesWebhooks
  publishes_webhooks "order", updated: -> { saved_change_to_status? }

  QUOTE_VALIDITY = 14.days
  SOURCES = %w[ shop online api hire ].freeze

  belongs_to :branch
  belongs_to :customer
  belongs_to :job, optional: true
  belongs_to :creator, class_name: "User", default: -> { Current.user }, optional: true
  has_many :lines, -> { order(:id) }, class_name: "CustomerOrderLine", dependent: :destroy, inverse_of: :customer_order
  has_many :deposits, -> { order(:id) }, dependent: :restrict_with_error
  has_many :sales, dependent: :restrict_with_error
  has_one :hire_agreement, dependent: :restrict_with_error

  enum :status, %w[ quote ordered ready collected cancelled ].index_by(&:itself), default: :quote

  money_attribute :total, :tax
  has_secure_token :tracking_token

  accepts_nested_attributes_for :lines, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["product_code"].blank? && attributes["quantity"].blank? }

  validates :source, inclusion: { in: SOURCES }
  validates_same_account :branch, :customer, :job
  validate(if: :job) { errors.add :job, "must be one of the customer's jobs" unless job.customer_id == customer_id }
  validate(if: -> { job && will_save_change_to_job_id? }) { errors.add :job, "is closed" if job.closed? }
  validate { errors.add :base, "Add at least one product" if lines.reject(&:marked_for_destruction?).empty? }
  validate(on: :update) { errors.add :base, "A #{status_was} order can't be changed" if lines.any?(&:changed_for_autosave?) && !status_was.in?(%w[ quote ordered ]) }

  before_validation(on: :create) { self.valid_until ||= Date.current + QUOTE_VALIDITY if quote? }
  before_create { self.number = DocumentSequence.next_number(branch, "customer_order") }
  before_save :total_up
  after_create { track_event "created", customer: customer.name, total: total_cents, status: status }

  scope :chronologically, -> { order(created_at: :desc, id: :desc) }
  scope :open, -> { where(status: %w[ ordered ready ]) }
  scope :online, -> { where(source: "online") }

  def reference
    "#{branch.code}-O#{number.to_s.rjust(5, "0")}"
  end
  alias_method :name, :reference

  # "MAI-O00012", as printed on quotes and orders.
  def self.find_by_reference(reference)
    code, number = reference.to_s.strip.upcase.split("-O", 2)
    joins(:branch).find_by(branches: { code: code }, number: number.to_i) if number.to_i.positive?
  end

  # The page an online customer follows their order on.
  def tracking_url
    Rails.application.routes.url_helpers.store_order_url(tracking_token, **Rails.configuration.action_mailer.default_url_options, subdomain: account.subdomain)
  end

  def kind
    quote? ? "Quote" : "Order"
  end

  def expired?
    quote? && valid_until.present? && valid_until < Date.current
  end

  # Hire orders are kept in step with their hire agreement, not edited by hand.
  def editable?
    (quote? || ordered?) && source != "hire"
  end

  # Prices on a quote hold for the customer, so they're worked out when a line is added and kept.
  def price_list
    customer&.price_list
  end

  private
    def total_up
      kept = lines.reject(&:marked_for_destruction?)
      kept.each(&:calculate_totals)
      self.total_cents = kept.sum(&:total_cents)
      self.tax_cents = kept.sum(&:tax_cents)
    end
end
