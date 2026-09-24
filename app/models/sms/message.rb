# A text to a customer, kept with what happened to it. Shops turn SMS on in their settings;
# each shop can send at most DAILY_LIMIT a day, so a mistake can't run up a bill.
class Sms::Message < ApplicationRecord
  include AccountOwned, Texts

  PURPOSES = %w[ receipt order_ready balance_reminder ].freeze
  DAILY_LIMIT = 500
  # Three SMS parts; longer texts cost more than they're worth.
  MAX_LENGTH = 459

  belongs_to :source, polymorphic: true, optional: true
  belongs_to :sender, class_name: "User", default: -> { Current.user }, optional: true

  enum :status, %w[ queued sent failed ].index_by(&:itself), default: :queued

  validates :recipient, format: { with: /\A254[17]\d{8}\z/, message: "must be a Kenyan mobile number like 0722 000 111" }
  validates :body, presence: true, length: { maximum: MAX_LENGTH }
  validates :purpose, inclusion: { in: PURPOSES }
  validate(on: :create) { errors.add :base, "SMS is turned off for this shop (Settings › SMS)" unless account&.sms_enabled? }
  validate(on: :create) { errors.add :base, "This shop has sent its #{DAILY_LIMIT} texts for today" if account && account.sms_messages.where(created_at: Time.current.all_day).count >= DAILY_LIMIT }

  after_create_commit :deliver_later

  scope :chronologically, -> { order(created_at: :desc) }

  def self.compose(to:, body:, purpose:, source: nil)
    create(recipient: PhoneNumber.normalize(to) || to.to_s, body: body.squish, purpose: purpose, source: source)
  end

  def deliver_later
    Sms::DeliveryJob.perform_later(self)
  end

  def deliver
    return unless queued?

    receipt = Sms::AfricasTalking.new.deliver(to: recipient, message: body)
    update!(status: :sent, provider_message_id: receipt.message_id, cost: receipt.cost, sent_at: Time.current)
  rescue Sms::AfricasTalking::Refused => error
    update!(status: :failed, error: error.message.first(250))
  end
end
