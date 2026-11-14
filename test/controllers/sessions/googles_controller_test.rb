require "test_helper"

class Sessions::GooglesControllerTest < ActionDispatch::IntegrationTest
  CLIENT_ID = "hardpoint-test.apps.googleusercontent.com"

  setup { Rails.configuration.x.google = { client_id: CLIENT_ID, client_secret: "shh" } }
  teardown { Rails.configuration.x.google = nil }

  test "the button is only there when Google sign-in is set up" do
    use_account accounts(:acme)
    get new_session_path
    assert_select "a[href=?]", new_session_google_path, text: "Sign in with Google"

    Rails.configuration.x.google = nil
    get new_session_path
    assert_select "a[href=?]", new_session_google_path, count: 0

    get new_session_google_path
    assert_redirected_to new_session_path
  end

  test "signing in with a Google address that's on the shop's staff" do
    google_vouches_for "amina@acme.test"
    sign_in_with_google accounts(:acme)

    assert_redirected_to root_url
    follow_redirect!
    assert_select "#user-menu", /Amina Owner/

    session = Account.without_isolation { Session.order(:id).last }
    assert session.signed_in_with_google?
    assert_equal "Google", Account.without_isolation { Event.where(action: "signed_in").order(:id).last.particulars["with"] }

    request = @google.last("/token")
    assert_equal "http://localhost/auth/google/callback", request.form[:redirect_uri]
    assert_equal "shh", request.form[:client_secret]
  end

  test "Google goes back to the bare domain, with the shop and a nonce in the state" do
    use_account accounts(:acme)
    get new_session_google_path

    location = URI(response.location)
    query = Rack::Utils.parse_query(location.query)
    assert_equal "accounts.google.com", location.host
    assert_equal CLIENT_ID, query["client_id"]
    assert_equal "http://localhost/auth/google/callback", query["redirect_uri"]
    assert_equal "openid email", query["scope"]
    assert_equal "acme", GoogleSignIn.subdomain_from(query["state"])
    assert query["nonce"].present?
  end

  test "an address that isn't on this shop's staff is turned away, and nobody is created" do
    google_vouches_for "bob@bolt.test" # an owner, but of another shop

    assert_no_difference -> { User.count } do
      sign_in_with_google accounts(:acme)
    end

    assert_redirected_to new_session_path
    assert_match "Nobody at", flash[:alert]
    assert cookies[:session_id].blank?
  end

  test "an address Google hasn't verified is refused" do
    google_vouches_for "amina@acme.test", email_verified: false
    sign_in_with_google accounts(:acme)

    assert_redirected_to new_session_path
    assert_match "didn't finish", flash[:alert]
    assert cookies[:session_id].blank?
  end

  test "a token for another client, from another issuer, expired, or for another sign-in is refused" do
    [ { aud: "someone-else.apps.googleusercontent.com" }, { iss: "https://accounts.evil.test" }, { exp: 1.minute.ago.to_i }, { nonce: "not-ours" } ].each do |wrong|
      google_vouches_for "amina@acme.test", **wrong
      sign_in_with_google accounts(:acme)

      assert_redirected_to new_session_path, "Expected #{wrong} to be refused"
      assert cookies[:session_id].blank?, "Expected #{wrong} not to sign anyone in"
    end
  end

  test "someone with two-factor on is still asked for their code" do
    secret = enable_two_factor_for(users(:amina))
    google_vouches_for "amina@acme.test"
    sign_in_with_google accounts(:acme)

    assert_redirected_to new_session_two_factor_path
    assert cookies[:session_id].blank?

    post session_two_factor_path, params: { code: current_code(secret) }
    assert cookies[:session_id].present?
    assert Account.without_isolation { Session.order(:id).last }.signed_in_with_google?
  end

  test "a handoff only works in the browser that started the sign-in, and only once" do
    google_vouches_for "amina@acme.test"
    use_account accounts(:acme)
    get new_session_google_path
    state, @nonce = Rack::Utils.parse_query(URI(response.location).query).values_at("state", "nonce")
    use_apex_domain
    get google_callback_path, params: { code: "from-google", state: state }
    handoff = response.location

    # Another browser (no nonce in its session) following the same link gets nowhere.
    open_session do |stranger|
      stranger.host! "acme.localhost"
      stranger.get handoff
      stranger.assert_redirected_to stranger.new_session_path
      assert stranger.cookies[:session_id].blank?
    end

    # The browser that started it signs in; the same link a second time doesn't.
    use_account accounts(:acme)
    get handoff
    assert cookies[:session_id].present?
    delete session_path
    get handoff
    assert_redirected_to new_session_path
    assert cookies[:session_id].blank?
  end

  test "a handoff for one shop is no good in another" do
    google_vouches_for "bob@bolt.test"
    use_account accounts(:acme)
    get new_session_google_path
    state, @nonce = Rack::Utils.parse_query(URI(response.location).query).values_at("state", "nonce")
    use_apex_domain
    get google_callback_path, params: { code: "from-google", state: state }
    token = Rack::Utils.parse_query(URI(response.location).query)["token"]

    use_account accounts(:bolt)
    get new_session_google_path # bolt's own nonce, as if a sign-in were under way there
    get session_google_path, params: { token: token }

    assert_redirected_to new_session_path
    assert cookies[:session_id].blank?
  end

  test "a forged or missing state never reaches Google" do
    google_vouches_for "amina@acme.test"
    use_apex_domain
    get google_callback_path, params: { code: "from-google", state: "made-up" }

    assert_redirected_to new_shop_lookup_path
    assert_empty @google.requests
  end

  test "backing out at Google lands on the shop's sign-in page" do
    google_vouches_for "amina@acme.test"
    use_account accounts(:acme)
    get new_session_google_path
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]

    use_apex_domain
    get google_callback_path, params: { error: "access_denied", state: state }
    assert_redirected_to "http://acme.localhost/session/google"

    use_account accounts(:acme)
    get session_google_path
    assert_redirected_to new_session_path
    assert_match "didn't finish", flash[:alert]
  end

  test "a closing shop only lets its owners in with Google too" do
    Account.without_isolation { accounts(:acme).update_columns(deletion_scheduled_for: 30.days.from_now) }

    google_vouches_for "carl@acme.test"
    sign_in_with_google accounts(:acme)

    assert_redirected_to new_session_path
    assert_match "closing", flash[:alert]
    assert cookies[:session_id].blank?
  end

  private
    # Google's token endpoint, answering with an ID token for +email+ that echoes the nonce it was asked for
    # (read from the state of the sign-in under way), unless a claim is overridden.
    def google_vouches_for(email, email_verified: true, **overrides)
      @google = fake_transport GoogleSignIn, "/token" => ->(_request) {
        claims = { iss: "https://accounts.google.com", aud: CLIENT_ID, exp: 5.minutes.from_now.to_i, nonce: @nonce,
          email: email, email_verified: email_verified }.merge(overrides)
        { id_token: [ "header", Base64.urlsafe_encode64(claims.to_json, padding: false), "signature" ].join(".") }
      }
    end

    # The whole round trip: the shop's button, Google (faked), the bare domain's callback, and back to the shop.
    def sign_in_with_google(account)
      use_account account
      get new_session_google_path
      query = Rack::Utils.parse_query(URI(response.location).query)
      @nonce = query["nonce"]

      use_apex_domain
      get google_callback_path, params: { code: "from-google", state: query["state"] }

      use_account account
      get response.location
    end
end
