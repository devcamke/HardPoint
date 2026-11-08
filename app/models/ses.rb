# Email through AWS SES. Settings come from the credentials under ses: (or config.x.ses in tests):
#
#   ses:
#     region: eu-west-1
#     access_key_id: …            # an IAM user allowed ses:SendEmail, ses:Get*, ses:PutSuppressedDestination,
#     secret_access_key: …        # ses:DeleteSuppressedDestination; sns:Publish isn't needed
#     configuration_set: hardpoint  # made by bin/rails ses:setup; carries bounces and complaints back
#     sns_topic_arn: arn:aws:sns:…  # the topic ses:setup made, so the webhook can check who's calling
#     smtp_username: …            # the older way in: SMTP credentials, used when there's no access key
#     smtp_password: …
#
# With an access key, mail goes through the SES API (Ses::Delivery) and the platform checks can ask SES how
# the account is doing; with only SMTP credentials, through SES's SMTP endpoint. Either way bounces and
# complaints come back through the configuration set's SNS topic to /webhooks/ses (Webhooks::SesController),
# and addresses that bounce or complain are not written to again (EmailSuppression).
module Ses
  mattr_writer :client, :sns_client

  def self.settings
    (Rails.configuration.x.ses.presence || Rails.application.credentials.ses || {}).to_h.symbolize_keys
  end

  def self.region = settings[:region].presence || "eu-west-1"
  def self.api? = settings[:access_key_id].present? && settings[:secret_access_key].present?
  def self.smtp? = settings[:smtp_username].present? && settings[:smtp_password].present?
  def self.configured? = api? || smtp?
  def self.configuration_set = settings[:configuration_set].presence || "hardpoint"
  def self.topic_arn = settings[:sns_topic_arn].presence

  # The domain mail is sent from, for the identity SES verifies: no-reply@hardpoint.app → hardpoint.app.
  def self.sending_domain
    Mail::Address.new(ApplicationMailer.default[:from].to_s).domain
  end

  def self.client
    @@client ||= Aws::SESV2::Client.new(**aws_options)
  end

  def self.sns_client
    @@sns_client ||= Aws::SNS::Client.new(**aws_options)
  end

  def self.aws_options
    { region: region, credentials: Aws::Credentials.new(settings[:access_key_id].to_s, settings[:secret_access_key].to_s) }
  end

  def self.reset_clients!
    @@client = @@sns_client = nil
  end

  # How the SES account is doing, for the platform checks and the admin Email page: whether it may send, whether
  # it's still in the sandbox, its reputation status and how much of today's quota is used.
  Account = Data.define(:sending_enabled, :production, :enforcement_status, :sent_last_24h, :max_24h, :max_per_second) do
    def healthy? = sending_enabled && enforcement_status == "HEALTHY"
    def quota_used_percent = max_24h.to_f.positive? ? (sent_last_24h.to_f / max_24h * 100).round : 0
  end

  def self.account
    response = client.get_account
    Account.new(response.sending_enabled, response.production_access_enabled, response.enforcement_status,
      response.send_quota&.sent_last_24_hours.to_f, response.send_quota&.max_24_hour_send.to_f, response.send_quota&.max_send_rate.to_f)
  end
end
