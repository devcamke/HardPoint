module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_account, :current_user

    def connect
      set_current_account && set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_account
        self.current_account = Account.find_by(subdomain: request.subdomain)
      end

      def set_current_user
        Current.set(account: current_account) do
          if session = current_account.sessions.find_by(id: cookies.signed[:session_id])
            self.current_user = session.user
          end
        end
      end
  end
end
