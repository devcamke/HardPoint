# Takes suppressed addresses out of every email before it's sent. An email left with nobody to send to isn't
# sent at all (the message is still built and logged, so a test can see it was dropped).
class EmailSuppression::Interceptor
  def self.delivering_email(mail)
    %i[ to cc bcc ].each do |field|
      addresses = mail.public_send(field)
      next if addresses.blank?

      kept = EmailSuppression.deliverable(addresses)
      mail.public_send(:"#{field}=", kept.presence) if kept.size != addresses.size
    end

    if mail.to.blank? && mail.cc.blank? && mail.bcc.blank?
      Rails.logger.info "EmailSuppression: not sending \"#{mail.subject}\": every recipient is suppressed"
      mail.perform_deliveries = false
    end
  end
end
