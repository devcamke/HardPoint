module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    # Things HardPoint support mustn't do while signed in as someone: hand out ways into the shop that outlive
    # the support session (API keys, webhooks) or take the shop's data away (exports, backups).
    def refuse_while_impersonated(back_to:, **options)
      before_action(**options) do
        redirect_to instance_exec(&back_to), alert: "Not while HardPoint support is signed in as you." if Current.session&.impersonated?
      end
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      if Current.account && cookies.signed[:session_id]
        Current.account.sessions.find_by(id: cookies.signed[:session_id]).then do |session|
          if session&.expired? || closed_to?(session) || left_the_shop?(session)
            session&.destroy && nil
          else
            session&.seen
            session
          end
        end
      end
    end

    # A session outlives nobody's membership: staff who were removed can't keep using a till left signed in, and
    # HardPoint support can't carry on as someone the shop has removed.
    def left_the_shop?(session)
      session && session.membership.nil?
    end

    # While a shop is closing, only its owners can use it.
    def closed_to?(session)
      session && Current.account.closing? && !session.membership&.owner?
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    # The end of signing in, however the person showed who they are (password, Google): a closing shop only lets its
    # owners in, and someone with two-factor on is asked for their code before any session starts.
    def sign_in(user, with:)
      if Current.account.closing? && !Current.account.memberships.find_by(user: user)&.owner?
        redirect_to new_session_path, alert: "#{Current.account.name} is closing; only its owners can sign in."
      elsif user.two_factor_enabled?
        session[:two_factor_challenge] = { "user_id" => user.id, "account_id" => Current.account.id, "started_at" => Time.current.to_i,
          "sign_in_method" => with.to_s }
        redirect_to new_session_two_factor_path
      else
        start_new_session_for user, sign_in_method: with
        redirect_to after_authentication_url
      end
    end

    def start_new_session_for(user, **attributes)
      Current.account.sessions.create!(user: user, user_agent: request.user_agent, ip_address: request.remote_ip, **attributes).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
