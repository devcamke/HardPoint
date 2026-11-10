# Placing a click-and-collect order from the online store: the customer (found by phone number, or
# added), a confirmed order at their chosen branch, a text and emails. No account or password needed.
class Storefront::Checkout
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :name, :string
  attribute :phone, :string
  attribute :email, :string
  attribute :branch_id, :integer
  attribute :note, :string
  attribute :website, :string # a field people can't see; bots fill it in

  attr_reader :order

  validates :name, presence: true, length: { maximum: 100 }
  validates :phone, presence: true
  validate { errors.add :phone, "must be a Kenyan mobile number like 0722 000 111" if phone.present? && !PhoneNumber.normalize(phone) }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :note, length: { maximum: 500 }
  validate { errors.add :branch_id, "choose where you'll collect" unless branch }

  def initialize(storefront:, cart:, **attributes)
    @storefront, @cart = storefront, cart
    super(**attributes)
    self.branch_id ||= storefront.collection_branches.first&.id if storefront.collection_branches.one?
  end

  def branch
    @storefront.collection_branches.find_by(id: branch_id)
  end

  def place
    return false unless valid?
    return errors.add(:base, "Your cart is empty") && false if @cart.empty?
    return errors.add(:base, "Something went wrong; please try again") && false if website.present?
    return false unless in_stock_at_branch?

    # The lines take the cart's prices with them, so the order confirms at the total the customer saw at checkout,
    # not re-priced for the branch's offers or a returning customer's price list.
    CustomerOrder.transaction do
      @order = account.customer_orders.create!(branch: branch, customer: customer, status: :ordered, ordered_at: Time.current, source: "online", note: order_note,
        lines_attributes: @cart.lines.map { { account: account, product_id: _1.product.id, quantity: _1.quantity, unit_price_cents: _1.unit_price_cents, promotion: _1.promotion } })
    end
    @cart.clear
    notify
    true
  rescue ActiveRecord::RecordInvalid => invalid
    errors.add :base, invalid.record.errors.full_messages.to_sentence
    false
  end

  private
    def account = @storefront.account

    # Two customers can't both be promised the last pallet: what's on hand less what earlier orders hold.
    def in_stock_at_branch?
      short = @cart.lines.select { |line| line.product.track_stock? && !line.product.kit? && line.product.available_at(branch) < line.quantity }
      short.each do |line|
        available = [ line.product.available_at(branch), 0 ].max
        errors.add :base, "Only #{available.to_s("F").delete_suffix(".0")} #{line.product.name} can be collected at #{branch.name} right now"
      end
      short.empty?
    end

    # Anyone can type any phone number here, so a customer the shop already has is never changed from the store:
    # the name and email typed go on the order's note for the shop to check, rather than onto their record.
    def customer
      @customer ||= known_customer || account.customers.create!(name: name.squish, phone: PhoneNumber.normalize(phone), email: email.presence)
    end

    def known_customer
      return @known_customer if defined?(@known_customer)
      @known_customer = account.customers.find_by_account_number(PhoneNumber.normalize(phone))
    end

    def order_note
      typed = ("Ordered online as #{[ name.squish, email.presence ].compact.join(", ")}" if known_customer)
      [ typed, note.presence ].compact.join(". ").first(500).presence
    end

    def notify
      Sms::Message.order_received(@order) if account.sms_enabled?
      StorefrontMailer.with(order: @order).new_order.deliver_later
      StorefrontMailer.with(order: @order).confirmation.deliver_later if @order.customer.email.present?
    end
end
