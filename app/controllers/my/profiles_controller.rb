class My::ProfilesController < ApplicationController
  allow_while_locked
  allow_without_two_factor

  def show
    @user = Current.user
    @membership = Current.membership
    @sessions_count = Current.account.sessions.where(user: Current.user).count
  end
end
