require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "email addresses are unique across shops" do
    user = User.new(name: "Copy", email_address: users(:bob).email_address, password: "password")

    assert_not user.valid?
    assert_includes user.errors[:email_address], "has already been taken"
  end
end
