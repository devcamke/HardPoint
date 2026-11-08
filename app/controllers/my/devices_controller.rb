# Where you're signed in at this shop: every session of yours, with the browser, where it came from and when it
# was last used, so a till that was replaced or a phone that went missing can be signed out from here.
class My::DevicesController < ApplicationController
  allow_while_locked
  allow_without_two_factor

  def index
    @sessions = my_sessions.newest_first.to_a
  end

  # One session, or every session but this one (id "others").
  def destroy
    if params[:id] == "others"
      my_sessions.where.not(id: Current.session.id).destroy_all
      redirect_to my_devices_path, notice: "Signed out everywhere else."
    else
      session = my_sessions.find(params[:id])
      session.destroy
      if session == Current.session
        cookies.delete(:session_id)
        redirect_to new_session_path, notice: "Signed out.", status: :see_other
      else
        redirect_to my_devices_path, notice: "That device is signed out.", status: :see_other
      end
    end
  end

  private
    def my_sessions
      Current.account.sessions.where(user: Current.user)
    end
end
