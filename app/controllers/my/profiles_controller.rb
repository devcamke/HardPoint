class My::ProfilesController < ApplicationController
  allow_without_two_factor

  def show
    @user = Current.user
    @membership = Current.membership
  end
end
