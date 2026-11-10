# Platform administrators set up two-factor only with a link made here, on the server, so someone who has
# learned an administrator's password can't enrol their own phone. A link lasts a day and works once.
#   bin/kamal app exec 'bin/rails "admin:enrolment_link[ada@hardpoint.app]"'
namespace :admin do
  desc "Print a one-time link for a platform administrator to set up two-factor"
  task :enrolment_link, [ :email ] => :environment do |_, args|
    user = User.find_by(email_address: args[:email].to_s.strip.downcase, admin: true)
    abort "No platform administrator with the email address #{args[:email].inspect}" unless user
    abort "#{user.email_address} already has two-factor on. Reset it first (in the console: User#disable_two_factor)." if user.two_factor_enabled?

    url_options = Rails.application.config.action_mailer.default_url_options.to_h
    puts Rails.application.routes.url_helpers.new_admin_session_url(**url_options, subdomain: "admin",
      enrolment_token: user.generate_token_for(:admin_enrolment))
    puts "It works once, until #{User::TwoFactor::ADMIN_ENROLMENT_EXPIRES_IN.from_now.to_fs(:long)}. Send it to #{user.name} privately."
  end
end
