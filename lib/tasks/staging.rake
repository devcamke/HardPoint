namespace :staging do
  # Staging is refreshed from production's backups (config/backup/refresh_staging.sh), so it must forget who
  # the people are: customers, suppliers, staff, payers. Shops, products, sales and figures stay as they are, so
  # the data is realistic. Also closes every door back to the real world: the M-Pesa, Airtel and eTIMS
  # connections become simulators, API keys and webhooks go, texts are switched off, and every password becomes
  # STAGING_PASSWORD (two-factor off), so the team can sign in to any shop.
  desc "Scramble personal data and real-world connections in a copy of production (staging only)"
  task anonymise: :environment do
    abort "staging:anonymise only runs where HARDPOINT_ENVIRONMENT=staging" unless Rails.configuration.x.staging
    password = ENV.fetch("STAGING_PASSWORD") { abort "Set STAGING_PASSWORD: every account gets it" }
    abort "STAGING_PASSWORD needs 10 characters or more" if password.length < 10

    Account.without_isolation do
      ActiveRecord::Base.transaction do
        Customer.in_batches.each_record do |customer|
          customer.update_columns(name: "Customer #{customer.id}", phone: ("2547#{customer.id.to_s.rjust(8, "0").last(8)}" if customer.phone.present?),
            email: ("customer-#{customer.id}@staging.hardpoint.test" if customer.email.present?), tax_pin: nil, address: nil)
        end
        Supplier.in_batches.update_all("contact_name = NULL, phone = NULL, email = CASE WHEN email IS NULL THEN NULL ELSE 'supplier-' || id || '@staging.hardpoint.test' END")
        User.in_batches.each_record do |user|
          user.update_columns(name: user.admin? ? user.name : "Staff #{user.id}", email_address: user.admin? ? user.email_address : "staff-#{user.id}@staging.hardpoint.test",
            password_digest: BCrypt::Password.create(password), two_factor_secret: nil, two_factor_recovery_codes: nil, two_factor_enabled_at: nil)
        end
        Membership.update_all(pin_digest: nil, approval_pin_digest: nil)
        Session.delete_all
        [ Mpesa::StkRequest, Mpesa::Transaction, Airtel::Request ].each { _1.update_all(phone: "254700000000") if _1.column_names.include?("phone") }
        Mpesa::Transaction.update_all(payer_name: "Payer") if Mpesa::Transaction.column_names.include?("payer_name")
        Mpesa::Shortcode.update_all(environment: "simulator", consumer_key: nil, consumer_secret: nil, passkey: nil)
        Airtel::Merchant.update_all(environment: "simulator", client_id: nil, client_secret: nil)
        Etims::Device.update_all(environment: "simulator")
        ApiKey.delete_all
        WebhookEndpoint.destroy_all
        AccountBackup.delete_all # the files are production's
        Account.update_all(sms_enabled: false, backup_frequency: "off")
      end
    end

    puts "Scrambled #{Account.without_isolation { Customer.count }} customers and #{User.count} users; every password is now STAGING_PASSWORD."
  end
end
