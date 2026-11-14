# "Sign in with Google" for shop staff: OpenID Connect's authorisation-code flow against Google, alongside
# passwords. Nobody is created this way: Google only vouches for an email address, and the person must already
# be on the shop's staff with that address. Two-factor, when they have it on, is still asked for afterwards.
#
# Google wants every redirect address listed, and can't list a wildcard, so Google sends people back to one
# address on the bare domain (/auth/google/callback) and they're handed on to their shop from there:
#
#   1. shop:  start      a random nonce goes in the shop's session and, signed with the shop's subdomain, in `state`
#   2. Google            the person picks their account
#   3. apex:  exchange   the code is swapped for an ID token, which is checked; the address goes into a signed
#                        handoff that lasts a minute and names the shop and the nonce
#   4. shop:  email_for  the handoff is only good in the shop it names and the browser whose session holds the
#                        nonce, and the nonce is spent as it's read, so a handoff that leaks can't be replayed
#
# Set up with `google: { client_id:, client_secret: }` in the credentials (an OAuth "Web application" client in
# Google Cloud whose redirect URI is https://APP_HOST/auth/google/callback); without them the button isn't shown.
class GoogleSignIn
  AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  ISSUERS = %w[ https://accounts.google.com accounts.google.com ].freeze
  STATE_EXPIRES_IN = 10.minutes
  HANDOFF_EXPIRES_IN = 1.minute

  # Google didn't vouch for anyone: the person backed out, the state is stale or forged, or the token is wrong.
  Refused = Class.new(StandardError)

  Started = Data.define(:nonce, :url)
  Handoff = Data.define(:subdomain, :token)

  class_attribute :transport, default: JsonHttp.new

  class << self
    def settings
      (Rails.configuration.x.google.presence || Rails.application.credentials.google || {}).to_h.symbolize_keys
    end

    def configured?
      settings[:client_id].present? && settings[:client_secret].present?
    end

    # Step 1: the nonce to keep in the shop's session, and where to send the browser.
    def start(account:, redirect_uri:)
      nonce = SecureRandom.urlsafe_base64(32)
      state = verifier.generate({ "subdomain" => account.subdomain, "nonce" => nonce }, purpose: :google_state, expires_in: STATE_EXPIRES_IN)
      query = { client_id: settings[:client_id], redirect_uri: redirect_uri, response_type: "code", scope: "openid email",
        state: state, nonce: nonce, prompt: "select_account" }

      Started.new(nonce: nonce, url: "#{AUTHORIZE_URL}?#{query.to_query}")
    end

    # Which shop a `state` came from, or nil; for sending someone who backed out at Google back to their shop.
    def subdomain_from(state)
      verifier.verified(state.to_s, purpose: :google_state)&.fetch("subdomain", nil)
    end

    # Step 3: swaps Google's code for the address it vouches for, as a handoff to the shop named in `state`.
    def exchange(code:, state:, redirect_uri:)
      started = verifier.verified(state.to_s, purpose: :google_state) or raise Refused, "state is invalid or has expired"
      raise Refused, "no code" if code.blank?

      response = transport.request(:post, TOKEN_URL, form: { code: code, client_id: settings[:client_id],
        client_secret: settings[:client_secret], redirect_uri: redirect_uri, grant_type: "authorization_code" })
      raise Refused, "Google refused the code (#{response.status})" unless response.success?

      email = verified_email(response.body["id_token"], nonce: started["nonce"])
      token = verifier.generate({ "subdomain" => started["subdomain"], "nonce" => started["nonce"], "email" => email },
        purpose: :google_handoff, expires_in: HANDOFF_EXPIRES_IN)
      Handoff.new(subdomain: started["subdomain"], token: token)
    end

    # Step 4: the address Google vouched for, if this handoff is for this shop and this browser's nonce.
    def email_for(token, account:, nonce:)
      handoff = verifier.verified(token.to_s, purpose: :google_handoff) or return
      return unless nonce.present? && handoff["subdomain"] == account.subdomain
      return unless ActiveSupport::SecurityUtils.secure_compare(handoff["nonce"].to_s, nonce.to_s)

      handoff["email"]
    end

    private
      def verifier
        Rails.application.message_verifier(:google_sign_in)
      end

      # The ID token comes straight from Google's token endpoint over TLS, which OpenID Connect accepts in place of
      # checking its signature (Core §3.1.3.7); what it says is still checked: who issued it, that it's for this
      # client and this sign-in (the nonce), that it's current, and that Google has verified the address.
      def verified_email(id_token, nonce:)
        claims = JSON.parse(Base64.urlsafe_decode64(id_token.to_s.split(".")[1].to_s))

        raise Refused, "not issued by Google" unless claims["iss"].in?(ISSUERS)
        raise Refused, "issued for another client" unless claims["aud"] == settings[:client_id]
        raise Refused, "token has expired" unless claims["exp"].to_i > Time.current.to_i
        raise Refused, "for another sign-in" unless ActiveSupport::SecurityUtils.secure_compare(claims["nonce"].to_s, nonce.to_s)
        raise Refused, "address isn't verified" unless claims["email_verified"].to_s == "true" && claims["email"].present?

        claims["email"].strip.downcase
      rescue JSON::ParserError, ArgumentError
        raise Refused, "unreadable ID token"
      end
  end
end
