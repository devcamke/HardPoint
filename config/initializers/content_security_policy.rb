# The content security policy: scripts only from this app (the importmap's inline script carries a
# nonce), no plugins, no framing, and forms that only post back here, to a shop's own subdomain or to
# Paystack's checkout. Inline styles are allowed: receipts and labels style themselves for printing,
# and a few bars and progress meters set their width inline.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.img_src     :self, :data, :blob
    policy.font_src    :self, :data
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none
    policy.manifest_src :self
    policy.worker_src  :self
    # The app itself (including Action Cable) and QZ Tray on the till's own computer.
    policy.connect_src :self, "wss://localhost:*", "ws://localhost:*", "wss://localhost.qz.io:*", "ws://localhost.qz.io:*"
    # Signup and "Sign in" continue on the shop's subdomain; card payments on Paystack.
    # (Evaluated in the controller, or on the request itself for pages rendered outside one, like a 404.)
    policy.form_action :self, -> {
      current = is_a?(ActionDispatch::Request) ? self : request
      "#{current.protocol}*.#{current.domain}#{current.port_string}"
    }, "https://checkout.paystack.com"
  end

  # One nonce per browser session, kept in the session, so it stays valid while Turbo swaps pages without
  # a full load (the session's id can't be used: a first visit has none yet).
  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[ script-src ]
end
