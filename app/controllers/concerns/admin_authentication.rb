module AdminAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_administrator
    helper_method :current_administrator
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_administrator, **options
    end
  end

  private
    def current_administrator
      @current_administrator ||= admin_session&.user
    end

    def admin_session
      @admin_session ||= AdminSession.find_by(id: cookies.signed[:admin_session_id]).then do |admin_session|
        admin_session if admin_session && !admin_session.expired? && admin_session.user.admin?
      end
    end

    def require_administrator
      redirect_to new_admin_session_path unless current_administrator
    end

    def start_admin_session_for(user)
      AdminSession.create!(user: user, user_agent: request.user_agent, ip_address: request.remote_ip).tap do |admin_session|
        cookies.signed[:admin_session_id] = { value: admin_session.id, httponly: true, same_site: :strict, expires: AdminSession::DURATION }
      end
    end

    def terminate_admin_session
      admin_session&.destroy
      cookies.delete(:admin_session_id)
    end
end
