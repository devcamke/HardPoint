# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # HardPoint: till and approval PINs, two-factor and recovery codes, people's phone numbers and KRA PINs,
  # signatures on webhooks and QZ Tray requests, and M-Pesa payers' details.
  :pin, /\Acode\z/, :phone, :msisdn, :kra, :signature, :passkey, :consumer, :recovery, :firstname, :middlename, :lastname
]
