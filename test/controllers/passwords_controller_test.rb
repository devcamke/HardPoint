require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:amina)
    use_account accounts(:acme)
  end

  test "new" do
    get new_password_path
    assert_response :success
  end

  test "create" do
    post passwords_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with PasswordsMailer, :reset, args: [ @user ], params: { account: accounts(:acme) }
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for an unknown user redirects but sends no mail" do
    post passwords_path, params: { email_address: "missing-user@example.com" }
    assert_enqueued_emails 0
    assert_redirected_to new_session_path

    follow_redirect!
    assert_notice "reset instructions sent"
  end

  test "create for someone from another shop sends no mail" do
    post passwords_path, params: { email_address: users(:bob).email_address }
    assert_enqueued_emails 0
  end

  test "the reset email links to the shop's subdomain" do
    perform_enqueued_jobs do
      post passwords_path, params: { email_address: @user.email_address }
    end

    assert_match %r{http://acme\.localhost/passwords/.+/edit}, ActionMailer::Base.deliveries.last.text_part.body.to_s
  end

  test "edit" do
    get edit_password_path(@user.password_reset_token)
    assert_response :success
  end

  test "edit with invalid password reset token" do
    get edit_password_path("invalid token")
    assert_redirected_to new_password_path

    follow_redirect!
    assert_notice "reset link is invalid"
  end

  test "edit with a token for someone from another shop" do
    get edit_password_path(users(:bob).password_reset_token)
    assert_redirected_to new_password_path
  end

  test "update" do
    assert_changes -> { @user.reload.password_digest } do
      put password_path(@user.password_reset_token), params: { password: "a-new-password", password_confirmation: "a-new-password" }
      assert_redirected_to new_session_path
    end

    follow_redirect!
    assert_notice "Password has been reset"
  end

  test "update with non matching passwords" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "first-password", password_confirmation: "doesnt-match" }
      assert_redirected_to edit_password_path(token)
    end

    follow_redirect!
    assert_notice "Password confirmation doesn't match"
  end

  test "update with a password that's too short" do
    token = @user.password_reset_token
    assert_no_changes -> { @user.reload.password_digest } do
      put password_path(token), params: { password: "short", password_confirmation: "short" }
    end
    follow_redirect!
    assert_notice "Password is too short"
  end

  private
    def assert_notice(text)
      assert_select "#notice, #alert", /#{text}/
    end
end
