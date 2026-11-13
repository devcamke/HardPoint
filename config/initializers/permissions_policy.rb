# Browser features HardPoint pages may use. The camera is for photographing signed delivery notes
# (through a file input); nothing uses the microphone, location, USB or payment request APIs.
#
# One source of truth, emitted under two header names: Rails' config.permissions_policy still writes the
# deprecated Feature-Policy header (`camera 'self'`), which current browsers ignore, so we also write the
# modern Permissions-Policy header (`camera=(self)`) ourselves from the same map. Keeping both covers old
# and new browsers without the two drifting apart.
module PermissionsPolicy
  # feature => :self (same origin only) or :none (disabled everywhere)
  FEATURES = {
    accelerometer: :none,
    camera:        :self,
    fullscreen:    :self,
    geolocation:   :none,
    gyroscope:     :none,
    magnetometer:  :none,
    microphone:    :none,
    payment:       :none,
    usb:           :none,
  }.freeze

  # Permissions-Policy syntax: `feature=(self)` or `feature=()` (empty allowlist = off).
  HEADER = FEATURES.map { |feature, value| "#{feature}=#{value == :self ? "(self)" : "()"}" }.join(", ").freeze

  # Adds the modern header to every response, alongside the Feature-Policy one Rails emits.
  class Middleware
    def initialize(app) = @app = app

    def call(env)
      status, headers, body = @app.call(env)
      headers["Permissions-Policy"] ||= HEADER
      [ status, headers, body ]
    end
  end
end

Rails.application.config.permissions_policy do |policy|
  PermissionsPolicy::FEATURES.each { |feature, value| policy.public_send(feature, value) }
end

Rails.application.config.middleware.use PermissionsPolicy::Middleware
