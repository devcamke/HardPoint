# What SES tells us about the emails we sent, through its SNS topic: a bounce, a complaint, a rejection. The
# SNS message's signature is checked against Amazon's certificate before anything in it is believed, and when
# the topic is known (credentials ses.sns_topic_arn) the message must come from it. SNS gets a 200 for anything
# that verifies; a message that doesn't is refused, and SNS gives up on it.
class Webhooks::SesController < ActionController::API
  rate_limit to: 600, within: 1.minute

  def create
    message = Sns::Message.parse(request.raw_post).verify!
    return head(:forbidden) if Ses.topic_arn && message.topic_arn != Ses.topic_arn

    if message.subscription_confirmation?
      message.confirm_subscription!
      Rails.logger.info "SES: confirmed the SNS subscription for #{message.topic_arn}"
    elsif message.notification?
      handle JSON.parse(message.message.to_s)
    end
    head :ok
  rescue Sns::Message::Invalid => error
    Rails.logger.warn "SES webhook refused: #{error.message}"
    head :forbidden
  rescue JSON::ParserError
    head :bad_request
  end

  private
    # SES event publishing ("eventType") and the older notifications ("notificationType") carry the same shapes.
    def handle(event)
      at = Time.zone.parse(event.dig("mail", "timestamp").to_s) || Time.current
      case event["eventType"] || event["notificationType"]
      when "Bounce"
        bounce = event["bounce"] || {}
        Array(bounce["bouncedRecipients"]).each do |recipient|
          EmailSuppression.record_bounce recipient["emailAddress"], bounce_type: bounce["bounceType"], bounce_subtype: bounce["bounceSubType"],
            detail: recipient["diagnosticCode"], at: at
        end
      when "Complaint"
        Array(event.dig("complaint", "complainedRecipients")).each do |recipient|
          EmailSuppression.record_complaint recipient["emailAddress"], detail: event.dig("complaint", "complaintFeedbackType"), at: at
        end
      when "Reject"
        # SES refused to send (a virus in an attachment, say): nothing wrong with the address. Worth knowing about.
        Rails.error.report(RuntimeError.new("SES rejected an email: #{event.dig("reject", "reason")}"), handled: true, severity: :error,
          context: { to: Array(event.dig("mail", "destination")).size })
      end
    end
end
