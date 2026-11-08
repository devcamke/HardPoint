# Setting AWS SES up for HardPoint from the command line, with the credentials under ses: (app/models/ses.rb).
# Run from a deployed app (bin/kamal app exec "bin/rails ses:setup"), because SNS confirms the webhook
# subscription by calling https://APP_HOST/webhooks/ses straight away.
namespace :ses do
  desc "Verify the sending domain, make the configuration set and bring bounces back to /webhooks/ses"
  task setup: :environment do
    abort "Add ses: { region:, access_key_id:, secret_access_key: } to the credentials first" unless Ses.api?
    domain = Ses.sending_domain
    client, sns = Ses.client, Ses.sns_client
    already = Aws::SESV2::Errors::AlreadyExistsException

    puts "Sending domain #{domain} (from #{ApplicationMailer.default[:from]})"
    begin
      client.create_email_identity(email_identity: domain)
      puts "  identity created"
    rescue already
      puts "  identity exists"
    end
    client.put_email_identity_mail_from_attributes(email_identity: domain, mail_from_domain: "mail.#{domain}", behavior_on_mx_failure: "USE_DEFAULT_VALUE")

    puts "Account-level suppression list: bounces and complaints"
    client.put_account_suppression_attributes(suppressed_reasons: %w[ BOUNCE COMPLAINT ])

    puts "Configuration set #{Ses.configuration_set}"
    begin
      client.create_configuration_set(configuration_set_name: Ses.configuration_set,
        reputation_options: { reputation_metrics_enabled: true }, suppression_options: { suppressed_reasons: %w[ BOUNCE COMPLAINT ] })
      puts "  created"
    rescue already
      puts "  exists"
    end

    webhook = Rails.application.routes.url_helpers.ses_webhook_url(**Rails.configuration.x.webhook_url_options)
    topic_arn = sns.create_topic(name: "hardpoint-ses-events").topic_arn
    sns.subscribe(topic_arn: topic_arn, protocol: "https", endpoint: webhook)
    puts "SNS topic #{topic_arn} → #{webhook} (the app confirms the subscription itself)"

    destination = { enabled: true, matching_event_types: %w[ BOUNCE COMPLAINT REJECT ], sns_destination: { topic_arn: topic_arn } }
    begin
      client.create_configuration_set_event_destination(configuration_set_name: Ses.configuration_set, event_destination_name: "hardpoint-sns", event_destination: destination)
    rescue already
      client.update_configuration_set_event_destination(configuration_set_name: Ses.configuration_set, event_destination_name: "hardpoint-sns", event_destination: destination)
    end
    puts "Bounces, complaints and rejections flow to the topic"

    puts "\nAdd to the credentials: ses: { sns_topic_arn: \"#{topic_arn}\" } so the webhook accepts only this topic."
    Rake::Task["ses:status"].invoke
  end

  desc "Show the domain's verification, DKIM and MAIL FROM status, the DNS records to add, and the account"
  task status: :environment do
    abort "Add ses: { region:, access_key_id:, secret_access_key: } to the credentials first" unless Ses.api?
    domain = Ses.sending_domain
    identity = Ses.client.get_email_identity(email_identity: domain)
    dkim, mail_from = identity.dkim_attributes, identity.mail_from_attributes
    account = Ses.account

    puts "\n#{domain}: #{identity.verified_for_sending_status ? "verified" : "NOT VERIFIED"}; DKIM #{dkim&.status}; MAIL FROM #{mail_from&.mail_from_domain_status || "not set"}"
    puts "SES account: sending #{account.sending_enabled ? "enabled" : "PAUSED"}, #{account.production ? "production" : "SANDBOX (verified addresses only; request production access in the SES console)"}, " \
         "reputation #{account.enforcement_status}, #{account.sent_last_24h.to_i}/#{account.max_24h.to_i} sent today, #{account.max_per_second} a second"

    puts "\nDNS records at #{domain} (Cloudflare: DNS only, not proxied):"
    Array(dkim&.tokens).each { puts "  CNAME  #{_1}._domainkey.#{domain}  →  #{_1}.dkim.amazonses.com" }
    puts "  MX     mail.#{domain}  →  10 feedback-smtp.#{Ses.region}.amazonses.com"
    puts "  TXT    mail.#{domain}  →  \"v=spf1 include:amazonses.com ~all\""
    puts "  TXT    _dmarc.#{domain}  →  \"v=DMARC1; p=none; rua=mailto:dmarc@#{domain}\"   (move to p=quarantine once reports look clean)"
    puts "\nWhen every status above says SUCCESS and the account is in production, email is ready (RUNBOOK §1 step 3)."
  end
end
