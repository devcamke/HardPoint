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

    CustomerOrder.transaction do
      @order = account.customer_orders.create!(branch: branch, customer: customer, status: :ordered, ordered_at: Time.current,
        source: "online", note: note.presence, lines_attributes: @cart.lines.map { { account: account, product_id: _1.product.id, quantity: _1.quantity } })
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

    def customer
      number = PhoneNumber.normalize(phone)
      account.customers.find_by_account_number(number)&.tap { |known| known.update!(email: email) if known.email.blank? && email.present? } ||
        account.customers.create!(name: name.squish, phone: number, email: email.presence)
    end

    def notify
      Sms::Message.order_received(@order) if account.sms_enabled?
      StorefrontMailer.with(order: @order).new_order.deliver_later
      StorefrontMailer.with(order: @order).confirmation.deliver_later if @order.customer.email.present?
    end
end
