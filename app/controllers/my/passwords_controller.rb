# Changing your password while signed in. It's the same sign-in for every shop you work for, so every other
# session, in every shop and in the admin area, is signed out; this one stays signed in.
class My::PasswordsController < ApplicationController
  allow_while_locked
  allow_without_two_factor
  # Per person: guesses at the current password from a till left signed in count however many tills there are.
  rate_limit to: 10, within: 3.minutes, only: :update, by: -> { "user-#{Current.user&.id}" },
    with: -> { redirect_to edit_my_password_path, alert: "Try again later." }

  before_action { redirect_to my_profile_path, alert: "Not while HardPoint support is signed in as you." if Current.session.impersonated? }

  MINIMUM_LENGTH = User::MINIMUM_PASSWORD_LENGTH

  def edit
  end

  def update
    user = Current.user
    if !user.authenticate(params[:current_password].to_s)
      @error = "Your current password wasn't right."
    elsif params[:password].to_s.length < MINIMUM_LENGTH
      @error = "Choose a new password of at least #{MINIMUM_LENGTH} characters."
    elsif params[:password] != params[:password_confirmation]
      @error = "The new passwords don't match."
    elsif !user.update(password: params[:password])
      @error = user.errors.full_messages.to_sentence
    end
    return render(:edit, status: :unprocessable_entity) if @error

    user.end_sessions(except: Current.session)
    user.track_event "password_changed"
    redirect_to my_profile_path, notice: "Your password is changed. You've been signed out everywhere else."
  end
end
