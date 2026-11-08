# An address HardPoint must not email again: it bounced for good (no such mailbox, domain gone) or its owner
# marked a message as spam. SES tells us through its SNS topic (Webhooks::SesController); the interceptor
# below then drops the address from every outgoing email, and the customer's or supplier's page says so.
# Platform-wide, not per shop: an address is the same mailbox whichever shop typed it. Lifting one (from the
# admin Email page, once the address is known to work) also removes it from SES's own suppression list.
class EmailSuppression < ApplicationRecord
  REASONS = %w[ bounce complaint manual ].freeze

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, presence: true, uniqueness: true
  validates :reason, inclusion: { in: REASONS }

  scope :newest_first, -> { order(event_at: :desc, id: :desc) }

  def self.suppressed?(email)
    email.present? && exists?(email: email.to_s.strip.downcase)
  end

  def self.for(email)
    find_by(email: email.to_s.strip.downcase) if email.present?
  end

  # Which of these addresses may still be written to.
  def self.deliverable(emails)
    emails = Array(emails).compact_blank
    return emails if emails.empty?

    blocked = where(email: emails.map { _1.to_s.strip.downcase }).pluck(:email)
    emails.reject { blocked.include?(_1.to_s.strip.downcase) }
  end

  # A bounce from SES: only permanent ones suppress (a full mailbox or a greylisting server is "Transient" and
  # worth trying again), and SES's own "OnAccountSuppressionList" bounces, which mean it's already blocked there.
  def self.record_bounce(email, bounce_type:, bounce_subtype: nil, detail: nil, at: Time.current)
    return unless bounce_type == "Permanent" || bounce_subtype == "OnAccountSuppressionList"

    record "bounce", email, detail: [ bounce_subtype, detail ].compact_blank.join(": "), at: at
  end

  def self.record_complaint(email, detail: nil, at: Time.current)
    record "complaint", email, detail: detail, at: at
  end

  def self.record(reason, email, detail: nil, at: Time.current)
    suppression = find_or_initialize_by(email: email.to_s.strip.downcase)
    suppression.assign_attributes(reason: reason, detail: detail.to_s.first(500).presence, event_at: at, count: suppression.count.to_i + 1)
    suppression.save!
    suppression
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Back in use: removed here and from SES's account-level list, so the next email goes.
  def lift!
    Ses.client.delete_suppressed_destination(email_address: email) if Ses.api?
    destroy!
  rescue Aws::SESV2::Errors::NotFoundException
    destroy!
  end

  def description
    case reason
    when "bounce" then "Emails to this address bounce"
    when "complaint" then "This address reported our email as spam"
    else "Emails to this address are stopped"
    end
  end
end
